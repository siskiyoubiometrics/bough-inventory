## Author: Hunter Stanke
library(dplyr)
library(tidyr)
library(rFIA)

##=====
##  Parameters ----
##=====
fia_dir <- 'data/FIA'
models <- readRDS(file.path(dirname(fia_dir), 'bough_models.rds'))
min_ht <- models$settings$min_ht
spcd <- models$spp$SPCD
metrics <- c('rule_boughs', 'rule_foliage_only', 'reach_boughs', 'reach_foliage_only')

##=====
##  Standing resource with the FIA sample design ----
##=====
db <- models$db
trees <- models$trees
listed <- tpa(db, landType = 'forest', treeType = 'live',
  treeDomain = SPCD %in% spcd & HT > min_ht,
  areaDomain = bough_land, treeList = TRUE)
## Keep the full condition denominator, including plots without target trees.
y <- listed %>%
  select(PLT_CN, EVAL_TYP, AREA_BASIS, CONDID, PROP_FOREST) %>%
  filter(!is.na(AREA_BASIS), PROP_FOREST > 0) %>% distinct()
x <- listed %>%
  select(PLT_CN, EVAL_TYP, TREE_BASIS, SUBP, TREE, TPA) %>%
  filter(!is.na(TREE_BASIS)) %>% distinct() %>%
  left_join(trees %>% select(PLT_CN, SUBP, TREE, species, all_of(metrics),
                            starts_with('linear_'), full_crown),
            by = c('PLT_CN', 'SUBP', 'TREE'))
if (anyNA(x$rule_boughs)) stop('Standing tree mass is missing.')
## A long table keeps the four material/scenario combinations readable.
values <- x %>%
  pivot_longer(all_of(metrics), names_to = 'metric', values_to = 'mass') %>%
  separate_wider_delim(metric, delim = '_', names = c('scenario', 'quantity'), too_many = 'merge') %>%
  mutate(mass = mass * TPA)
## customPSE retains tree sampling bases and covariance within the fir group.
est <- customPSE(db, x = values, xVars = c(TPA, mass),
  xGrpBy = c(species, scenario, quantity), y = y, yVars = PROP_FOREST)
area_est <- customPSE(db, x = y, xVars = c(acres = PROP_FOREST),
  y = y, yVars = PROP_FOREST)
write.csv(area_est, 'output/standing_area.csv', row.names = FALSE)
support <- values %>% group_by(species, scenario, quantity) %>%
  summarise(positive_mass_plots = n_distinct(PLT_CN[mass > 0]),
            tree_records = n(), .groups = 'drop')
standing <- est %>%
  transmute(YEAR, species, route = 'A', scenario, quantity,
    green_tons_total = mass_TOTAL, total_se_percent = mass_SE,
    green_tons_per_acre = mass_RATIO, per_acre_se_percent = mass_RATIO_SE,
    nonreserved_acres = PROP_FOREST_TOTAL, area_se_percent = area_est$acres_SE,
    live_trees_per_acre = TPA_RATIO, tpa_se_percent = TPA_RATIO_SE,
    species_plots = nPlots_x, area_plots = nPlots_y,
    notes = 'Material quantities; see coverage and README assumptions') %>%
  left_join(support, by = c('species', 'scenario', 'quantity'))

## Retain Route B NA rows and the separate whole-crown envelope.
b <- standing %>%
  filter(species == 'red fir (Shasta, California and noble)',
         scenario == 'rule', quantity == 'boughs') %>%
  mutate(route = 'B', scenario = 'published', quantity = 'UNAVAILABLE',
    green_tons_total = NA_real_, total_se_percent = NA_real_,
    green_tons_per_acre = NA_real_, per_acre_se_percent = NA_real_,
    positive_mass_plots = NA_real_, notes = 'See NOTES.md: Limits')
crown <- x %>% mutate(full_crown = full_crown * TPA)
crown_est <- customPSE(db, x = crown, xVars = full_crown, xGrpBy = species,
  y = y, yVars = PROP_FOREST)
envelope <- b %>%
  select(-green_tons_total, -green_tons_per_acre, -total_se_percent,
         -per_acre_se_percent) %>%
  left_join(crown_est %>% select(species, green_tons_total = full_crown_TOTAL,
    green_tons_per_acre = full_crown_RATIO, total_se_percent = full_crown_SE,
    per_acre_se_percent = full_crown_RATIO_SE), by = 'species') %>%
  mutate(route = 'B physical envelope from A', scenario = 'whole crown',
    quantity = 'full_crown', positive_mass_plots = species_plots,
    notes = 'Zero to full NSVB crown; not a Blatner prediction or harvest estimate')
envelope_zero <- envelope %>%
  mutate(quantity = 'zero', green_tons_total = 0, green_tons_per_acre = 0,
    total_se_percent = NA_real_, per_acre_se_percent = NA_real_,
    positive_mass_plots = 0)
standing <- bind_rows(standing, b, envelope_zero, envelope) %>%
  mutate(coverage = models$settings$coverage,
    allocation = models$settings$allocation,
    green_ratio_used = models$settings$green_ratio)
write.csv(standing, 'output/standing_by_species.csv', row.names = FALSE, na = 'NA')

## Estimate all species together so combined errors retain covariance.
totals <- customPSE(db, x = values, xVars = mass,
  xGrpBy = c(scenario, quantity), y = y, yVars = PROP_FOREST)
write.csv(totals, 'output/standing_totals.csv', row.names = FALSE)

## Estimate the linear allocation on exactly the same standing sample.
linear_values <- x %>%
  select(-all_of(metrics), -ends_with('fraction')) %>%
  pivot_longer(c(linear_rule_boughs, linear_rule_foliage_only,
                 linear_reach_boughs, linear_reach_foliage_only),
    names_to = c('allocation', 'scenario', 'quantity'),
    names_pattern = '(linear)_(rule|reach)_(boughs|foliage_only)',
    values_to = 'mass') %>%
  mutate(mass = mass * TPA)
linear <- customPSE(db, x = linear_values, xVars = mass,
  xGrpBy = c(scenario, quantity), y = y, yVars = PROP_FOREST)
write.csv(linear, 'output/linear_sensitivity.csv', row.names = FALSE)

##=====
##  Independent estimator check of the same crown inputs ----
##=====
components <- c('STEM', 'STEM_BARK', 'BRANCH', 'FOLIAGE', 'STUMP',
  'STUMP_BARK', 'BOLE', 'BOLE_BARK', 'SAWLOG', 'SAWLOG_BARK', 'BG', 'AG')
db$TREE[paste0('DRYBIO_', components)] <- NA_real_
index <- match(db$TREE$CN, trees$CN)
db$TREE$DRYBIO_FOLIAGE <- trees$foliage_lb[index]
db$TREE$DRYBIO_BRANCH <- trees$branches_lb[index]
crosscheck <- biomass(db, component = c('FOLIAGE', 'BRANCH'),
  treeDomain = SPCD %in% spcd & HT > min_ht, areaDomain = bough_land, totals = TRUE)
custom_crown <- customPSE(db, x = crown, xVars = full_crown,
  y = y, yVars = PROP_FOREST)
if (!isTRUE(all.equal(crosscheck$BIO_TOTAL * models$settings$green_ratio,
                      custom_crown$full_crown_TOTAL, tolerance = 1e-8))) {
  stop('The independent crown expansion check differs.')
}

saveRDS(list(x = x, y = y, estimates = est, standing = standing),
  file.path(dirname(fia_dir), 'standing.rds'))
print(standing %>% filter(route == 'A', scenario == 'rule'))
