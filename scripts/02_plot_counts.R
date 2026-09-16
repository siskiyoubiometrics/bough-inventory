## Author: Hunter Stanke
library(dplyr)
library(rFIA)

##=====
##  Parameters ----
##=====
fia_dir <- 'data/FIA'
state <- 'OR'
region <- 6
forest <- 10
district <- NA
spcd <- c('20/21/22', '81', '119', '15', '202', '122')
spp <- tibble(SPCD = spcd,
  species = c('red fir (Shasta, California and noble)', 'Incense-cedar',
              'Western white pine', 'White fir', 'Douglas-fir', 'Ponderosa pine'))

##=====
##  Latest completed inventory evaluation ----
##=====
## Which plot measurements belong to the latest published Oregon evaluation?
db <- readRDS(file.path(dirname(fia_dir), 'inventory.rds'))
recent <- clipFIA(db, mostRecent = TRUE)
## Merge the three recorded fir codes before counting distinct plots.
db$TREE <- db$TREE %>%
  mutate(SPCD = if_else(SPCD %in% c(20, 21, 22), '20/21/22', as.character(SPCD)))

## Which records represent current measurements rather than retained predecessors?
## clipFIA retains previous visits for change estimation. Count only prev == 0.
plots <- recent$PLOT %>%
  filter(prev == 0) %>%
  select(-PLT_CN, -pltID, -prev)

## Which inventory years and sampling cycles actually remain in this selection?
years <- plots %>%
  count(INVYR, CYCLE, name = 'plots') %>%
  arrange(INVYR, CYCLE)
write.csv(years, 'output/selected_inventory_years.csv', row.names = FALSE)
evals <- db$POP_EVAL %>%
  left_join(db$POP_EVAL_TYP %>%
              select(EVAL_CN, EVAL_TYP), by = c('CN' = 'EVAL_CN')) %>%
  group_by(STATECD, EVAL_TYP) %>%
  filter(END_INVYR == max(END_INVYR, na.rm = TRUE)) %>%
  ungroup() %>%
  select(EVALID, EVAL_TYP, START_INVYR, END_INVYR, EVAL_DESCR) %>%
  arrange(EVALID, EVAL_TYP)
write.csv(evals, 'output/selected_evaluations.csv', row.names = FALSE)

##=====
##  Forest and ranger district assignment ----
##=====
## Which forest and ranger district does FIA assign to each plot?
## FIA makes this PLOTGEOM assignment from the exact plot location, so the
## assignment is not affected by public coordinate fuzzing and swapping.
## Join PLOTGEOM.CN to PLOT.CN using the recorded assignment.
plots <- plots %>%
  left_join(db$PLOTGEOM %>%
              mutate(geometry_present = TRUE), by = 'CN') %>%
  mutate(remeasured = !is.na(PREV_PLT_CN) & !is.na(REMPER))

## Retain the plot-level forest assignment for these unweighted counts.
woods <- plots %>%
  filter(FVS_REGION == region, FVS_FOREST == forest)

##=====
##  Forested plots and live trees ----
##=====
## How many forested plots support each live-tree species, including remeasurements?
## Counts are unweighted records, not expanded tree totals or estimates of acres.
## A forested plot has PLOT_STATUS_CD == 1; a live tree has STATUSCD == 1.
base <- woods %>%
  filter(PLOT_STATUS_CD == 1)
cohorts <- bind_rows(
  base %>%
    mutate(sample = 'All forested plots'),
  base %>%
    filter(remeasured) %>%
    mutate(sample = 'Remeasured forested plots'))
samples <- tibble(sample = c('All forested plots', 'Remeasured forested plots'))
totals <- cohorts %>%
  count(sample, name = 'forested_plots')
trees <- db$TREE %>%
  filter(STATUSCD == 1) %>%
  inner_join(cohorts %>%
               select(CN, sample), by = c('PLT_CN' = 'CN'),
             relationship = 'many-to-many')
counts <- trees %>%
  filter(SPCD %in% spcd) %>%
  group_by(sample, SPCD) %>%
  summarise(plots_with_live_species = n_distinct(PLT_CN),
            live_tree_records = n(), .groups = 'drop')
forest_counts <- cross_join(samples, spp) %>%
  left_join(totals, by = 'sample') %>%
  left_join(counts, by = c('sample', 'SPCD')) %>%
  mutate(forested_plots = coalesce(forested_plots, 0),
         plots_with_live_species = coalesce(plots_with_live_species, 0),
         live_tree_records = coalesce(live_tree_records, 0),
         scope = 'Rogue River portion of the Rogue River-Siskiyou National Forest (administrative forest code 610)',
         status = 'Available') %>%
  select(scope, sample, SPCD, species, forested_plots,
         plots_with_live_species, live_tree_records, status)
write.csv(forest_counts, 'output/plot_counts_forest.csv', row.names = FALSE)

## What can be reported for High Cascades without inventing a district assignment?
## Leave the district parameter NA until a verified PLOTGEOM code is available.
district_counts <- cross_join(samples, spp) %>%
  mutate(scope = 'High Cascades Ranger District',
         forested_plots = NA_real_, plots_with_live_species = NA_real_,
         live_tree_records = NA_real_,
         status = 'Unavailable: district cannot be identified') %>%
  select(scope, sample, SPCD, species, forested_plots,
         plots_with_live_species, live_tree_records, status)

## How would the same counts be calculated once the district code is identified?
if (!is.na(district)) {
  district_plots <- cohorts %>%
    filter(FVS_DISTRICT == district)
  district_totals <- district_plots %>%
    count(sample, name = 'forested_plots')
  district_trees <- db$TREE %>%
    filter(STATUSCD == 1, SPCD %in% spcd) %>%
    inner_join(district_plots %>%
                 select(CN, sample), by = c('PLT_CN' = 'CN'),
               relationship = 'many-to-many') %>%
    group_by(sample, SPCD) %>%
    summarise(plots_with_live_species = n_distinct(PLT_CN),
              live_tree_records = n(), .groups = 'drop')
  district_counts <- cross_join(samples, spp) %>%
    left_join(district_totals, by = 'sample') %>%
    left_join(district_trees, by = c('sample', 'SPCD')) %>%
    mutate(forested_plots = coalesce(forested_plots, 0),
           plots_with_live_species = coalesce(plots_with_live_species, 0),
           live_tree_records = coalesce(live_tree_records, 0),
           scope = 'High Cascades Ranger District', status = 'Available') %>%
    select(scope, sample, SPCD, species, forested_plots,
           plots_with_live_species, live_tree_records, status)
}
write.csv(district_counts, 'output/plot_counts_district.csv',
          row.names = FALSE, na = 'NA')

print(forest_counts)
print(district_counts)
