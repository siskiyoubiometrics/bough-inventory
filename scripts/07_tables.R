## Author: Hunter Stanke
library(dplyr)
library(tidyr)
library(knitr)
library(ggplot2)
library(scales)

## Read calculated estimates and keep their full precision until display.
forest.standing <- read.csv('output/standing_by_species.csv') %>%
  filter(route == 'A')
forest.total <- read.csv('output/standing_totals.csv') %>%
  transmute(species = 'Combined', scenario, quantity,
    green_tons_total = mass_TOTAL, total_se_percent = mass_SE,
    green_tons_per_acre = mass_RATIO, per_acre_se_percent = mass_RATIO_SE)
standing <- bind_rows(forest.standing, forest.total) %>%
  mutate(domain = 'Forest') %>%
  bind_rows(read.csv('output/district_standing.csv') %>%
    mutate(domain = 'High Cascades proxy', scenario = 'rule'))
change <- read.csv('output/regrowth_components.csv') %>%
  filter(component != 'survivor_change') %>%
  mutate(domain = 'Forest') %>%
  bind_rows(read.csv('output/district_change.csv') %>%
    mutate(domain = 'High Cascades proxy', scenario = 'rule'))

## Use one display table so every total and per-acre error follows the same rule.
results <- bind_rows(
  standing %>% transmute(domain, species, scenario, quantity, component = 'Standing',
    total = green_tons_total, per_acre = green_tons_per_acre,
    total_se_percent, per_acre_se_percent),
  change %>% transmute(domain, species, scenario, quantity, component,
    total = green_tons_per_year, per_acre = green_tons_acre_year,
    total_se_percent, per_acre_se_percent)) %>%
  mutate(flagged = coalesce(total_se_percent > 100, FALSE) |
           coalesce(per_acre_se_percent > 100, FALSE),
    species = case_when(
      species == 'incense-cedar' ~ 'Incense-cedar',
      species == 'ponderosa pine' ~ 'Ponderosa pine',
      species == 'western white pine' ~ 'Western white pine',
      species == 'white fir' ~ 'White fir',
      TRUE ~ species),
    quantity = if_else(quantity == 'boughs', 'Boughs', 'Foliage only'),
    component = case_when(
      component %in% c('gross_accrual', 'survivor_accrual') ~ 'Gross accrual',
      component == 'survivor_loss' ~ 'Survivor loss',
      component %in% c('ingrowth_gain', 'ingrowth') ~ 'Ingrowth',
      component %in% c('mortality_loss', 'mortality') ~ 'Mortality',
      component %in% c('removal_loss', 'removals') ~ 'Removals',
      component == 'net_change' ~ 'Net change',
      TRUE ~ component),
    scenario = if_else(scenario == 'rule', 'Lower third', 'Reach limit'),
    flag = if_else(flagged, 'not distinguishable from zero', '')) %>%
  arrange(domain, scenario, species == 'Combined', species, quantity, component)
shown <- results %>%
  mutate(total = sprintf('%.0f', total), per_acre = sprintf('%.3f', per_acre),
    total_se_percent = if_else(is.na(total_se_percent), 'NA',
      paste0(sprintf('%.1f', total_se_percent), if_else(total_se_percent > 100, '*', ''))),
    per_acre_se_percent = if_else(is.na(per_acre_se_percent), 'NA',
      paste0(sprintf('%.1f', per_acre_se_percent), if_else(per_acre_se_percent > 100, '*', '')))) %>%
  rename(Species = species, Material = quantity, Component = component,
    Total = total, `Total error (%)` = total_se_percent,
    `Per acre` = per_acre, `Per-acre error (%)` = per_acre_se_percent, Flag = flag)

## Put the lower-third estimates in the README and retain reach results in CSVs.
forest.standing.table <- shown %>%
  filter(domain == 'Forest', scenario == 'Lower third', Component == 'Standing') %>%
  select(Species, Material, Total, `Total error (%)`, `Per acre`, `Per-acre error (%)`, Flag)
forest.change.table <- shown %>%
  filter(domain == 'Forest', scenario == 'Lower third', Component != 'Standing') %>%
  select(Species, Material, Component, Total, `Total error (%)`, `Per acre`, `Per-acre error (%)`, Flag)
district.standing.table <- shown %>%
  filter(domain == 'High Cascades proxy', Component == 'Standing') %>%
  select(Species, Material, Total, `Total error (%)`, `Per acre`, `Per-acre error (%)`, Flag)
district.change.table <- shown %>%
  filter(domain == 'High Cascades proxy', Component != 'Standing') %>%
  select(Species, Material, Component, Total, `Total error (%)`, `Per acre`, `Per-acre error (%)`, Flag)
readme <- readLines('README.md')
start <- match('<!-- results:start -->', readme)
end <- match('<!-- results:end -->', readme)
writeLines(c(readme[1:start], '', '### Forest standing material', '',
  kable(forest.standing.table, format = 'pipe'), '', '### Forest annual change components', '',
  kable(forest.change.table, format = 'pipe'), '', '### District proxy standing material', '',
  kable(district.standing.table, format = 'pipe'), '', '### District proxy annual change components', '',
  kable(district.change.table, format = 'pipe'), '', readme[end:length(readme)]), 'README.md')

## Name every uncertain net-change row, including the forest reach scenario.
uncertain <- shown %>% filter(Component == 'Net change', flagged) %>%
  select(Domain = domain, Zone = scenario, Species, Material,
    `Total error (%)`, `Per-acre error (%)`)
notes <- readLines('NOTES.md')
start <- match('<!-- uncertain:start -->', notes)
end <- match('<!-- uncertain:end -->', notes)
writeLines(c(notes[1:start], '', kable(uncertain, format = 'pipe'), '',
  notes[end:length(notes)]), 'NOTES.md')

## Report the actual estimation samples separately from unweighted forest counts.
forest.area <- read.csv('output/standing_area.csv')
growth.area <- read.csv('output/regrowth_area.csv')
counts <- read.csv('output/plot_counts.csv')
district.standing <- read.csv('output/district_standing.csv') %>% filter(species == 'Combined')
district.change <- read.csv('output/district_change.csv') %>%
  filter(species == 'Combined', component == 'net_change')
support <- c(paste0('The most recent reporting year is ', forest.area$YEAR,
  '. The forest standing sample includes ', forest.area$nPlots_y,
  ' domain plots, and the change sample includes ', growth.area$nPlots_y,
  ' remeasured domain plots. The forest change calculation excludes ',
  sum(counts$excluded_unlinked), ' tree records with missing required previous measurements.'), '',
  paste0('The district proxy includes ', first(district.standing$area_plots),
  ' standing domain plots and ', first(district.change$area_plots),
  ' remeasured domain plots. It has ', first(district.standing$species_plots),
  ' plots with eligible target trees and excludes ', first(district.change$excluded_unlinked),
  ' tree records from affected change components because required previous measurements are missing.'))
notes <- readLines('NOTES.md')
start <- match('<!-- support:start -->', notes)
end <- match('<!-- support:end -->', notes)
writeLines(c(notes[1:start], '', support, '', notes[end:length(notes)]), 'NOTES.md')

## Mark large errors at each plotted estimate, including combined net change.
figure.data <- results %>% filter(component %in% c('Standing', 'Net change')) %>%
  mutate(mark = if_else(flagged, '*', ''))
forest.figure <- figure.data %>% filter(domain == 'Forest', component == 'Standing') %>%
  ggplot(aes(total, species)) + geom_col(fill = 'darkseagreen4') +
  geom_text(aes(label = mark), size = 6, nudge_y = 0.25) +
  facet_grid(scenario ~ quantity, scales = 'free_x') +
  scale_x_continuous(labels = label_comma()) + theme_bw() +
  labs(x = 'Green US short tons', y = NULL, title = 'Standing bough material',
    subtitle = first(forest.standing$coverage),
    caption = '* Not distinguishable from zero: total or per-acre sampling error exceeds 100%.')
ggsave('output/standing_by_species.png', forest.figure, width = 13, height = 8, dpi = 150)
forest.figure <- figure.data %>% filter(domain == 'Forest', component == 'Net change') %>%
  ggplot(aes(total, species)) + geom_col(fill = 'steelblue4') +
  geom_vline(xintercept = 0) + geom_text(aes(label = mark), size = 6, nudge_y = 0.25) +
  facet_grid(scenario ~ quantity, scales = 'free_x') +
  scale_x_continuous(labels = label_comma()) + theme_bw() +
  labs(x = 'Green US short tons/year', y = NULL, title = 'Observed net inventory change',
    subtitle = first(forest.standing$coverage),
    caption = '* Not distinguishable from zero: total or per-acre sampling error exceeds 100%.')
ggsave('output/regrowth_by_species.png', forest.figure, width = 13, height = 8, dpi = 150)
district.figure <- figure.data %>% filter(domain == 'High Cascades proxy', component == 'Standing') %>%
  ggplot(aes(total, species)) + geom_col(fill = 'darkseagreen4') +
  geom_text(aes(label = mark), size = 6, nudge_y = 0.25) +
  facet_wrap(~ quantity, scales = 'free_x') +
  scale_x_continuous(labels = label_comma()) + theme_bw() +
  labs(x = 'Green US short tons', y = NULL, title = 'Standing bough material',
    subtitle = 'High Cascades ecoregion proxy, lower-third height zone',
    caption = '* Not distinguishable from zero: total or per-acre sampling error exceeds 100%.')
ggsave('output/district_standing.png', district.figure, width = 13, height = 5, dpi = 150)
district.figure <- figure.data %>% filter(domain == 'High Cascades proxy', component == 'Net change') %>%
  ggplot(aes(total, species)) + geom_col(fill = 'steelblue4') +
  geom_vline(xintercept = 0) + geom_text(aes(label = mark), size = 6, nudge_y = 0.25) +
  facet_wrap(~ quantity, scales = 'free_x') +
  scale_x_continuous(labels = label_comma()) + theme_bw() +
  labs(x = 'Green US short tons/year', y = NULL, title = 'Observed net inventory change',
    subtitle = 'High Cascades ecoregion proxy, lower-third height zone',
    caption = '* Not distinguishable from zero: total or per-acre sampling error exceeds 100%.')
ggsave('output/district_change.png', district.figure, width = 13, height = 5, dpi = 150)
