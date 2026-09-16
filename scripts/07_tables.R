## Author: Hunter Stanke
library(dplyr)
library(tidyr)
library(knitr)
library(ggplot2)
library(scales)

## Keep calculated estimates at full precision until display.
standing <- read.csv('output/standing.csv')
change <- read.csv('output/change.csv')
results <- bind_rows(
  standing %>% transmute(species, scenario, quantity, component = 'Standing',
    total = green_tons_total, per_acre = green_tons_per_acre,
    total_se_percent, total_lower_95, total_upper_95, species_plots, per_acre_se_percent),
  change %>% transmute(species, scenario, quantity, component,
    total = green_tons_per_year, per_acre = green_tons_acre_year,
    total_se_percent, per_acre_se_percent)) %>%
  mutate(flagged = coalesce(total_se_percent > 100, FALSE) |
           coalesce(per_acre_se_percent > 100, FALSE),
    quantity = if_else(quantity == 'boughs', 'Boughs', 'Foliage only'),
    component = case_when(
      component == 'gross_accrual' ~ 'Gross accrual',
      component == 'survivor_loss' ~ 'Survivor loss',
      component == 'ingrowth_gain' ~ 'Ingrowth',
      component == 'mortality_loss' ~ 'Mortality',
      component == 'removal_loss' ~ 'Removals',
      component == 'net_change' ~ 'Net change',
      TRUE ~ component),
    scenario = if_else(scenario == 'rule', 'Lower third', 'Reach limit'),
    flag = if_else(flagged, 'not distinguishable from zero', '')) %>%
  arrange(scenario, species == 'Combined', species, quantity,
    match(component, c('Standing', 'Gross accrual', 'Survivor loss', 'Ingrowth',
                       'Mortality', 'Removals', 'Net change')))
shown <- results %>%
  mutate(total = sprintf('%.0f', total), per_acre = sprintf('%.3f', per_acre),
    interval = paste0(sprintf('%.0f', total_lower_95), ' to ', sprintf('%.0f', total_upper_95)),
    total_se_percent = if_else(is.na(total_se_percent), 'NA',
      paste0(sprintf('%.1f', total_se_percent), if_else(total_se_percent > 100, '*', ''))),
    per_acre_se_percent = if_else(is.na(per_acre_se_percent), 'NA',
      paste0(sprintf('%.1f', per_acre_se_percent), if_else(per_acre_se_percent > 100, '*', '')))) %>%
  rename(Species = species, Material = quantity, Component = component,
    Total = total, `Total error (%)` = total_se_percent, `95% interval` = interval,
    Plots = species_plots, `Per acre` = per_acre, `Per-acre error (%)` = per_acre_se_percent,
    Flag = flag)

## Lead with boughs cut to the bole; retain both materials and zones in the CSVs.
standing.table <- shown %>%
  filter(scenario == 'Lower third', Component == 'Standing', Material == 'Boughs') %>%
  select(Species, Total, `Total error (%)`, `95% interval`, Plots,
         `Per acre`, `Per-acre error (%)`, Flag)
change.table <- shown %>%
  filter(scenario == 'Lower third', Component != 'Standing', Material == 'Boughs') %>%
  select(Species, Component, Total, `Total error (%)`, `Per acre`, `Per-acre error (%)`, Flag)
readme <- readLines('README.md')
start <- match('<!-- results:start -->', readme)
end <- match('<!-- results:end -->', readme)
writeLines(c(readme[1:start], '', '## Standing boughs', '',
  'Standing totals and their intervals are green US short tons of foliage and branch wood cut to the bole in the lower-third height zone.', '',
  kable(standing.table, format = 'pipe'), '',
  'Plots count distinct plots with eligible trees in each species group, including trees with zero modeled mass in the harvest zone.', '',
  '## Annual change components', '',
  'Annual totals are green US short tons per year in the same lower-third height zone.', '',
  kable(change.table, format = 'pipe'), '', readme[end:length(readme)]), 'README.md')

## Name every flagged net-change row, including foliage and reach scenarios.
uncertain <- shown %>% filter(Component == 'Net change', flagged) %>%
  select(Zone = scenario, Species, Material, `Total error (%)`, `Per-acre error (%)`)
notes <- readLines('NOTES.md')
start <- match('<!-- uncertain:start -->', notes)
end <- match('<!-- uncertain:end -->', notes)
writeLines(c(notes[1:start], '', kable(uncertain, format = 'pipe'), '',
  notes[end:length(notes)]), 'NOTES.md')

## Describe actual area plots, target-tree plots and excluded links separately.
counts <- read.csv('output/plot_counts.csv') %>% filter(species == 'Combined')
support <- c(paste0('The most recent reporting year is ', first(standing$YEAR), '.'), '',
  paste0('The standing sample contains ', counts$standing_area_plots,
    ' domain plots, including ', counts$standing_species_plots,
    ' plots with eligible target trees.'), '',
  paste0('The change sample contains ', counts$growth_area_plots, ' remeasured domain plots.'), '',
  paste0('The change calculation excludes ', counts$excluded_unlinked,
    ' tree records from affected components because required previous measurements are missing.'))
notes <- readLines('NOTES.md')
start <- match('<!-- support:start -->', notes)
end <- match('<!-- support:end -->', notes)
writeLines(c(notes[1:start], '', support, '', notes[end:length(notes)]), 'NOTES.md')

## Show one domain in each figure, with both modeled materials and height zones.
figure.data <- results %>% filter(component %in% c('Standing', 'Net change')) %>%
  mutate(mark = if_else(flagged, '*', ''))
standing.figure <- figure.data %>% filter(component == 'Standing') %>%
  ggplot(aes(total, species)) + geom_col(fill = 'darkseagreen4') +
  geom_text(aes(label = mark), size = 6, nudge_y = 0.25) +
  facet_grid(scenario ~ quantity, scales = 'free_x') +
  scale_x_continuous(labels = label_comma()) + theme_bw() +
  labs(x = 'Green US short tons', y = NULL, title = 'Standing bough material',
    subtitle = first(standing$coverage),
    caption = '* Not distinguishable from zero: total or per-acre sampling error exceeds 100%.')
ggsave('output/standing.png', standing.figure, width = 14, height = 8, dpi = 150)
change.figure <- figure.data %>% filter(component == 'Net change') %>%
  ggplot(aes(total, species)) + geom_col(fill = 'steelblue4') +
  geom_vline(xintercept = 0) + geom_text(aes(label = mark), size = 6, nudge_y = 0.25) +
  facet_grid(scenario ~ quantity, scales = 'free_x') +
  scale_x_continuous(labels = label_comma()) + theme_bw() +
  labs(x = 'Green US short tons/year', y = NULL, title = 'Observed net inventory change',
    subtitle = first(standing$coverage),
    caption = '* Not distinguishable from zero: total or per-acre sampling error exceeds 100%.')
ggsave('output/change.png', change.figure, width = 14, height = 8, dpi = 150)
cat(paste(kable(standing.table, format = 'pipe'), collapse = '\n'), '\n')
