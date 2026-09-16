## Author: Hunter Stanke
library(dplyr)
library(rFIA)
library(tidyr)

##=====
##  Parameters ----
##=====
fia_dir <- 'data/FIA'
## Domain, height, reach, and moisture are inherited from script 03.
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
area_est <- customPSE(db, x = y, xVars = c(acres = PROP_FOREST),
  y = y, yVars = PROP_FOREST)

## Publish component totals, ratios and errors for species and combined.
components <- bind_rows(estimate, totals %>% mutate(species = 'Combined')) %>%
  select(YEAR, species, scenario, quantity,
    starts_with('net_change_'),
    starts_with('gross_accrual_'), starts_with('survivor_loss_'),
    starts_with('ingrowth_gain_'), starts_with('mortality_loss_'),
    starts_with('removal_loss_')) %>%
  pivot_longer(-c(YEAR, species, scenario, quantity),
    names_to = c('component', '.value'),
    names_pattern = '(.+?)_(TOTAL|RATIO_SE|RATIO|SE)$') %>%
  rename(green_tons_per_year = TOTAL, total_se_percent = SE,
    green_tons_acre_year = RATIO, per_acre_se_percent = RATIO_SE) %>%
  mutate(total_se_tons_per_year = abs(green_tons_per_year) * total_se_percent / 100,
    per_acre_se_tons_year = abs(green_tons_acre_year) * per_acre_se_percent / 100,
    area_plots = area_est$nPlots_y, nonreserved_acres = area_est$acres_TOTAL,
    area_se_percent = area_est$acres_SE,
    coverage = models$settings$coverage, allocation = models$settings$allocation,
    green_ratio_used = models$settings$green_ratio)
## Count nonzero component plots and missing links within each group.
support <- changes %>%
  pivot_longer(c(net_change, gross_accrual, survivor_loss, ingrowth_gain,
                 mortality_loss, removal_loss),
    names_to = 'component', values_to = 'annual_ton')
support <- bind_rows(support, support %>% mutate(species = 'Combined')) %>%
  group_by(species, scenario, quantity, component) %>%
  summarise(component_plots = n_distinct(PLT_CN[annual_ton != 0]),
    excluded_unlinked = sum(missing_required_previous), .groups = 'drop')
components <- components %>%
  left_join(support, by = c('species', 'scenario', 'quantity', 'component'))
write.csv(components, 'output/change.csv', row.names = FALSE, na = 'NA')

## Retain local records for the sample checks in script 06.
saveRDS(list(pairs = x, changes = changes, area = y),
  file.path(dirname(fia_dir), 'regrowth.rds'))
print(components %>% filter(scenario == 'rule', quantity == 'boughs'))
