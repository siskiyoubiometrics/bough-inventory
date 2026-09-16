## Author: Hunter Stanke
library(dplyr)
library(tidyr)

## Read the single standing and change samples.
fia_dir <- 'data/FIA'
standing <- read.csv('output/standing.csv')
components <- read.csv('output/change.csv')
growth <- readRDS(file.path(dirname(fia_dir), 'regrowth.rds'))

## Count actual plots and missing links once for each reporting group.
support <- bind_rows(growth$pairs,
                     growth$pairs %>% mutate(species = 'Combined')) %>%
  group_by(species) %>%
  summarise(framework_species_plots = n_distinct(PLT_CN),
    matched_plots = n_distinct(PLT_CN[survivor & linked]),
    matched_survivors = sum(survivor & linked),
    ingrowth_records = sum(ingrowth), mortality_records = sum(mortality),
    removal_records = sum(removal),
    excluded_unlinked = sum(missing_required_previous),
    excluded_plots = n_distinct(PLT_CN[missing_required_previous]),
    .groups = 'drop')
counts <- standing %>% filter(scenario == 'rule', quantity == 'boughs') %>%
  select(species, standing_area_plots = area_plots,
    standing_species_plots = species_plots,
    standing_positive_mass_plots = positive_mass_plots,
    standing_tree_records = tree_records) %>%
  left_join(support, by = 'species') %>%
  mutate(growth_area_plots = n_distinct(growth$area$PLT_CN))
write.csv(counts, 'output/plot_counts.csv', row.names = FALSE)

## Check the annual balance after population expansion.
balance <- components %>%
  select(species, scenario, quantity, component, green_tons_per_year) %>%
  pivot_wider(names_from = component, values_from = green_tons_per_year) %>%
  mutate(expected_net = gross_accrual + survivor_loss + ingrowth_gain -
           mortality_loss - removal_loss)
stopifnot(isTRUE(all.equal(balance$net_change, balance$expected_net,
                          tolerance = 1e-8)))

## Check the species totals against the independently estimated combined rows.
standing_sum <- standing %>% filter(species != 'Combined') %>%
  group_by(scenario, quantity) %>%
  summarise(species_sum = sum(green_tons_total), .groups = 'drop') %>%
  left_join(standing %>% filter(species == 'Combined') %>%
    select(scenario, quantity, green_tons_total), by = c('scenario', 'quantity'))
stopifnot(isTRUE(all.equal(standing_sum$species_sum, standing_sum$green_tons_total,
                          tolerance = 1e-8)))
stopifnot(all(standing$area_plots == n_distinct(readRDS(
            file.path(dirname(fia_dir), 'standing.rds'))$y$PLT_CN)))
stopifnot(all(standing$interval_df == standing$area_plots - 1),
          all(standing$interval_df > 0),
          all(standing$total_lower_95 <= standing$green_tons_total),
          all(standing$total_upper_95 >= standing$green_tons_total))

## Record the software used for every regenerated result.
packages <- c('dplyr', 'tidyr', 'ggplot2', 'knitr', 'scales', 'rFIA', 'merchandiser')
software <- tibble(package = c('R', packages),
  version = c(as.character(getRversion()),
    vapply(packages, function(package) as.character(packageVersion(package)), character(1))))
write.csv(software, 'output/software_versions.csv', row.names = FALSE)
print(counts)
cat('Standing totals, intervals and annual component balances checked.\n')
