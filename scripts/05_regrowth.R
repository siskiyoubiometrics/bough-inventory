## Author: Hunter Stanke
library(dplyr)
library(rFIA)
library(tidyr)

##=====
##  Parameters ----
##=====
fia_dir <- 'data/FIA'
## Forest, district, height, reach, and moisture are inherited from script 03.
models <- readRDS(file.path(dirname(fia_dir), 'bough_models.rds'))
spcd <- models$spp$SPCD
metrics <- c('rule_boughs', 'rule_foliage_only', 'reach_boughs', 'reach_foliage_only')

##=====
##  Growth evaluation and remeasurement links ----
##=====
## Which FIA growth records and area weights describe remeasured forest?
db <- models$db
## This vintage's midpoint table lacks SPCD, required by rFIA 1.1.4.
## Recover the observed code by tree key, without inventing a species.
if (!'SPCD' %in% names(db$TREE_GRM_MIDPT)) {
  db$TREE_GRM_MIDPT <- db$TREE_GRM_MIDPT %>%
    left_join(db$TREE %>% select(TRE_CN = CN, SPCD), by = 'TRE_CN')
}
growth <- growMort(db, grpBy = SPCD, landType = 'forest', treeType = 'all',
  treeDomain = SPCD %in% spcd, areaDomain = bough_land, treeList = TRUE)
## The growth framework supplies domain indicators, sample bases, annual
## mortality/removal factors, ingrowth factors, and the growth-area denominator.
## Do not use current-volume population weights for this change estimate.
y <- growth %>%
  select(PLT_CN, EVAL_TYP, AREA_BASIS, CONDID, PROP_FOREST) %>%
  filter(!is.na(AREA_BASIS), PROP_FOREST > 0) %>% distinct()
remeasured_plots <- db$PLOT %>%
  filter(!is.na(PREV_PLT_CN), !is.na(REMPER), REMPER > 0) %>% pull(CN)
if (any(!y$PLT_CN %in% remeasured_plots)) stop('Growth plots are not remeasured.')
x <- growth %>%
  select(PLT_CN, EVAL_TYP, TREE_BASIS, SUBP, TREE, SPCD,
         RECR_TPA, MORT_TPA, REMV_TPA, CURR_TPA, PREV_TPA) %>%
  filter(!is.na(TREE_BASIS), SPCD %in% spcd) %>% distinct() %>%
  left_join(db$TREE %>% select(PLT_CN, SUBP, TREE, CN, PREV_TRE_CN, STATUSCD),
             by = c('PLT_CN', 'SUBP', 'TREE')) %>%
  left_join(db$PLOT %>% select(PLT_CN = CN, PREV_PLT_CN, REMPER),
             by = 'PLT_CN') %>%
  filter(!is.na(PREV_PLT_CN), !is.na(REMPER), REMPER > 0) %>%
  left_join(models$trees %>% select(CN, all_of(metrics)), by = 'CN') %>%
  left_join(models$trees %>%
    select(PREV_TRE_CN = CN, previous_plot = PLT_CN,
           previous_ht = HT, previous_dia = DIA, previous_cr = CR,
           all_of(metrics)) %>%
    rename_with(~ paste0(.x, '_previous'), all_of(metrics)),
    by = 'PREV_TRE_CN')
## Previous measurements must be the plot's actual previous visit.
if (any(x$previous_plot != x$PREV_PLT_CN, na.rm = TRUE)) {
  stop('Previous tree does not belong to the previous plot.')
}
## Missing mortality/removal rates on INGROWTH rows are structural zeros.
## Their positive recruitment factor already identifies them as new trees.
x <- x %>%
  left_join(models$spp, by = 'SPCD') %>%
  mutate(ingrowth = coalesce(RECR_TPA > 0, FALSE),
         mortality = coalesce(MORT_TPA > 0, FALSE),
         removal = coalesce(REMV_TPA > 0, FALSE),
         survivor = coalesce(CURR_TPA > 0 & !ingrowth, FALSE),
         linked = !is.na(rule_boughs_previous),
         missing_required_previous = (survivor | mortality | removal) & !linked)
audit <- x %>% group_by(species) %>%
  summarise(framework_records = n(),
    matched_survivors = sum(survivor & linked),
    ingrowth_records = sum(ingrowth), mortality_records = sum(mortality),
    removal_records = sum(removal),
    excluded_unlinked = sum(missing_required_previous),
    excluded_plots = n_distinct(PLT_CN[missing_required_previous]),
    .groups = 'drop')

##=====
##  Annual components on the same remeasured plots ----
##=====
## Pair each scenario's current mass with its own previous mass.
changes <- x %>%
  pivot_longer(all_of(metrics), names_to = 'metric', values_to = 'current_mass') %>%
  mutate(previous_mass = case_when(
    metric == 'rule_boughs' ~ rule_boughs_previous,
    metric == 'rule_foliage_only' ~ rule_foliage_only_previous,
    metric == 'reach_boughs' ~ reach_boughs_previous,
    metric == 'reach_foliage_only' ~ reach_foliage_only_previous),
    current_mass = if_else(STATUSCD == 1, current_mass, 0))
## Reject missing active endpoint inputs before computing annual changes.
if (any(is.na(changes$current_mass[changes$survivor | changes$ingrowth])) ||
    any(is.na(changes$previous_mass[changes$linked]))) {
  stop('A required growth endpoint mass is missing.')
}
## Split each survivor's change before summing to plots or species.
changes <- changes %>%
  mutate(survivor_change = if_else(survivor & linked,
      CURR_TPA * (current_mass - previous_mass) / REMPER, 0),
    gross_accrual = pmax(survivor_change, 0),
    survivor_loss = pmin(survivor_change, 0),
    ingrowth_gain = if_else(ingrowth, RECR_TPA * current_mass, 0),
    mortality_loss = if_else(mortality & linked, MORT_TPA * previous_mass, 0),
    removal_loss = if_else(removal & linked, REMV_TPA * previous_mass, 0),
    net_change = gross_accrual + survivor_loss + ingrowth_gain -
      mortality_loss - removal_loss) %>%
  separate_wider_delim(metric, delim = '_', names = c('scenario', 'quantity'), too_many = 'merge')
## FIA recruitment, mortality and removal factors are already annualized.
if (anyNA(changes$net_change)) stop('Annual change contains missing mass.')
estimate <- customPSE(db, x = changes,
  xVars = c(net_change, survivor_change, gross_accrual, survivor_loss,
            ingrowth_gain, mortality_loss, removal_loss),
  xGrpBy = c(species, scenario, quantity), y = y, yVars = PROP_FOREST)
totals <- customPSE(db, x = changes,
  xVars = c(net_change, survivor_change, gross_accrual, survivor_loss,
            ingrowth_gain, mortality_loss, removal_loss),
  xGrpBy = c(scenario, quantity), y = y, yVars = PROP_FOREST)
write.csv(totals, 'output/regrowth_totals.csv', row.names = FALSE)
support <- changes %>% group_by(species, scenario, quantity) %>%
  summarise(change_plots = n_distinct(PLT_CN[net_change != 0]),
    matched_plots = n_distinct(PLT_CN[survivor & linked]),
    survivor_change_plots = n_distinct(PLT_CN[survivor_change != 0]),
    gross_accrual_plots = n_distinct(PLT_CN[gross_accrual > 0]),
    survivor_loss_plots = n_distinct(PLT_CN[survivor_loss < 0]),
    ingrowth_mass_plots = n_distinct(PLT_CN[ingrowth_gain > 0]),
    mortality_mass_plots = n_distinct(PLT_CN[mortality_loss > 0]),
    removal_mass_plots = n_distinct(PLT_CN[removal_loss > 0]), .groups = 'drop')
regrowth <- estimate %>%
  transmute(YEAR, species, scenario, quantity,
    net_green_tons_per_year = net_change_TOTAL,
    net_total_se_percent = net_change_SE,
    net_green_tons_acre_year = net_change_RATIO,
    net_per_acre_se_percent = net_change_RATIO_SE,
    survivor_green_tons_per_year = survivor_change_TOTAL,
    survivor_total_se_percent = survivor_change_SE,
    gross_accrual_green_tons_per_year = gross_accrual_TOTAL,
    gross_accrual_total_se_percent = gross_accrual_SE,
    survivor_loss_green_tons_per_year = survivor_loss_TOTAL,
    survivor_loss_total_se_percent = survivor_loss_SE,
    ingrowth_green_tons_per_year = ingrowth_gain_TOTAL,
    ingrowth_total_se_percent = ingrowth_gain_SE,
    mortality_green_tons_per_year = mortality_loss_TOTAL,
    mortality_total_se_percent = mortality_loss_SE,
    removal_green_tons_per_year = removal_loss_TOTAL,
    removal_total_se_percent = removal_loss_SE,
    nonreserved_growth_acres = PROP_FOREST_TOTAL,
    framework_species_plots = nPlots_x, area_plots = nPlots_y) %>%
  left_join(support, by = c('species', 'scenario', 'quantity')) %>%
  left_join(audit, by = 'species')
area_est <- customPSE(db, x = y, xVars = c(acres = PROP_FOREST),
  y = y, yVars = PROP_FOREST)
write.csv(area_est, 'output/regrowth_area.csv', row.names = FALSE)
regrowth <- regrowth %>%
  mutate(area_se_percent = area_est$acres_SE,
    allocation = models$settings$allocation,
    green_ratio_used = models$settings$green_ratio,
    notes = 'Observed-component net; unlinked survivors excluded; not postharvest recovery')
write.csv(regrowth, 'output/regrowth_by_species.csv', row.names = FALSE, na = 'NA')

## Publish component totals, ratios and errors for species and combined.
components <- bind_rows(estimate, totals %>% mutate(species = 'Combined')) %>%
  select(YEAR, species, scenario, quantity,
    starts_with('net_change_'), starts_with('survivor_change_'),
    starts_with('gross_accrual_'), starts_with('survivor_loss_'),
    starts_with('ingrowth_gain_'), starts_with('mortality_loss_'),
    starts_with('removal_loss_')) %>%
  pivot_longer(-c(YEAR, species, scenario, quantity),
    names_to = c('component', '.value'),
    names_pattern = '(.+?)_(TOTAL|RATIO_SE|RATIO|SE)$') %>%
  rename(green_tons_per_year = TOTAL, total_se_percent = SE,
    green_tons_acre_year = RATIO, per_acre_se_percent = RATIO_SE) %>%
  mutate(total_se_tons_per_year = abs(green_tons_per_year) * total_se_percent / 100,
    per_acre_se_tons_year = abs(green_tons_acre_year) * per_acre_se_percent / 100)
write.csv(components, 'output/regrowth_components.csv', row.names = FALSE, na = 'NA')

##=====
##  Sample counts and software ----
##=====
standing <- read.csv('output/standing_by_species.csv')
counts <- standing %>% filter(route == 'A', scenario == 'rule', quantity == 'boughs') %>%
  select(species, standing_area_plots = area_plots,
    standing_species_plots = species_plots,
    standing_positive_rule_plots = positive_mass_plots,
    standing_tree_records = tree_records) %>%
  left_join(regrowth %>% filter(scenario == 'rule', quantity == 'boughs') %>%
    select(species, growth_area_plots = area_plots, framework_species_plots,
      matched_plots, change_plots, matched_survivors, ingrowth_records,
      mortality_records, removal_records, excluded_unlinked, excluded_plots),
    by = 'species')
write.csv(counts, 'output/plot_counts.csv', row.names = FALSE)
saveRDS(list(changes = changes, area = y, regrowth = regrowth),
  file.path(dirname(fia_dir), 'regrowth.rds'))
software <- tibble(package = c('R', 'dplyr', 'tidyr', 'ggplot2', 'knitr', 'scales', 'rFIA', 'merchandiser'),
  version = c(as.character(getRversion()), as.character(packageVersion('dplyr')),
    as.character(packageVersion('tidyr')), as.character(packageVersion('ggplot2')),
    as.character(packageVersion('knitr')), as.character(packageVersion('scales')),
    as.character(packageVersion('rFIA')),
    as.character(packageVersion('merchandiser'))))
write.csv(software, 'output/software_versions.csv', row.names = FALSE)
print(regrowth %>% filter(scenario == 'rule'))
