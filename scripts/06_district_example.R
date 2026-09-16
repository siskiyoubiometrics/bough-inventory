## Author: Hunter Stanke
## High Cascades proxy on the Rogue River portion of the Rogue River-Siskiyou
## National Forest (administrative forest code 610).
## ECOSUBCD is assigned from public, fuzzed and swapped coordinates, so this
## proxy is approximate. FIA assigns PLOTGEOM.FVS_DISTRICT from exact locations,
## but that district field is empty in this vintage.
## Cascades: M242Bb, M242Be, M242Bg, M261Dh = High Cascades proxy.
## Klamath Mountains: M261Ae, M261Ao, M261Av = Siskiyou Mountains proxy.
library(rFIA)
library(dplyr)
library(merchandiser)
library(tidyr)

## Choose the public inventory and district proxy
fia_dir <- 'data/FIA'
forest_codes <- c(610)
ecoregions <- c('M242Bb', 'M242Be', 'M242Bg', 'M261Dh')
spcd <- c(20, 21, 22, 81, 119, 15, 202, 122)

## Read the conversion and harvest rules from the source ledger
sources <- read.csv('data/sources.csv')
green_ratio <- as.numeric(sources$value[sources$id == 'green_moderate'])
tonne_factor <- as.numeric(sources$value[sources$id == 'tonne_to_short_ton'])
min_ht <- as.numeric(sources$value[sources$id == 'min_ht'])
fractions <- sources %>%
  filter(id %in% c('zone_fraction', 'removal_cap')) %>%
  separate_wider_delim(value, delim = '/', names = c('numerator', 'denominator')) %>%
  mutate(fraction = as.numeric(numerator) / as.numeric(denominator))
zone_fraction <- fractions$fraction[fractions$id == 'zone_fraction']
removal_cap <- fractions$fraction[fractions$id == 'removal_cap']

## Read Oregon subset and select the latest completed evaluation
db <- readFIA(fia_dir, states = 'OR')

## Keep both visits' forest assignments before clipFIA drops previous PLOTGEOM rows
forest_plots <- db$PLOTGEOM %>%
  filter(FVS_LOC_CD %in% forest_codes) %>%
  pull(CN)
db <- clipFIA(db, mostRecent = TRUE)

## Carry the ecoregion code onto the condition table so the area domain can see it
db$COND <- db$COND %>%
  left_join(db$PLOT %>% select(PLT_CN = CN, ECOSUBCD), by = 'PLT_CN')

## Save the same area domain on COND for both growth endpoints
db$COND <- db$COND %>%
  mutate(district_land = RESERVCD == 0 & PLT_CN %in% forest_plots &
           ECOSUBCD %in% ecoregions)

## Preserve the recorded species when estimating crown mass.
tree.list <- tpa(db,
                 treeList = TRUE,
                 bySpecies = TRUE,
                 treeDomain = HT > min_ht & SPCD %in% spcd,
                 areaDomain = RESERVCD == 0 &
                   FVS_LOC_CD %in% forest_codes &
                   ECOSUBCD %in% ecoregions,
                 grpBy = c(DIA, HT, CR)) %>%
  ## NSVB biomass in dry metric tonnes by component
  mutate(biomass(dbh = DIA, ht = HT, spcd = SPCD)) %>%
  mutate(crown_base = HT - CR / 100 * HT,
         p = if_else(CR == 0, 0,
           pmax(0, pmin(1, (HT * zone_fraction - crown_base) / (CR / 100 * HT)))),
         ## Cone with apex at the top, uniform density; apply the removal cap
         share = pmin(removal_cap, 1 - (1 - p)^3),
         bough_ton = (dry_foliage + dry_branches) * share * TPA *
           tonne_factor * green_ratio,
         foliage_ton = dry_foliage * share * TPA * tonne_factor * green_ratio,
         COMMON_NAME = if_else(SPCD %in% c(20, 21, 22),
           'red fir (Shasta, California and noble)', COMMON_NAME))

## Estimate boughs (foliage plus branches) and foliage_only (foliage only) on the proxy
bough_resource_by_species <- customPSE(db,
                                       x = select(tree.list, -c(AREA_BASIS)),
                                       xVars = c(bough_ton, foliage_ton, TPA),
                                       xGrpBy = COMMON_NAME,
                                       y = select(tree.list, -c(TREE_BASIS)),
                                       yVars = PROP_FOREST,
                                       totals = TRUE)

## Estimate the combined resource with covariance between species
bough_resource_total <- customPSE(db,
                                  x = select(tree.list, -c(AREA_BASIS)),
                                  xVars = c(bough_ton, foliage_ton, TPA),
                                  y = select(tree.list, -c(TREE_BASIS)),
                                  yVars = PROP_FOREST,
                                  totals = TRUE)

## Count actual domain and species plots separately from the full design sample
standing.support <- tree.list %>%
  filter(!is.na(TREE_BASIS), TPA > 0) %>%
  bind_rows(tree.list %>% filter(!is.na(TREE_BASIS), TPA > 0) %>%
              mutate(COMMON_NAME = 'Combined')) %>%
  group_by(species = COMMON_NAME) %>%
  summarise(species_plots = n_distinct(PLT_CN), .groups = 'drop')
standing.area <- tree.list %>%
  filter(PROP_FOREST > 0) %>%
  summarise(area_plots = n_distinct(PLT_CN))

## Save both material quantities with their sampling errors and plot counts
standing <- bind_rows(bough_resource_by_species,
                     bough_resource_total %>% mutate(COMMON_NAME = 'Combined')) %>%
  select(YEAR, species = COMMON_NAME, nPlots_x, nPlots_y, PROP_FOREST_TOTAL,
         starts_with('bough_ton_'), starts_with('foliage_ton_')) %>%
  pivot_longer(starts_with(c('bough_ton_', 'foliage_ton_')),
               names_to = c('material', '.value'),
               names_pattern = '(.+?)_(TOTAL|RATIO_SE|RATIO|SE)$') %>%
  transmute(YEAR, species, quantity = if_else(material == 'bough_ton', 'boughs', 'foliage_only'),
            green_tons_total = TOTAL, total_se_percent = SE,
            green_tons_per_acre = RATIO, per_acre_se_percent = RATIO_SE,
            total_se_tons = abs(TOTAL) * SE / 100,
            design_plots = nPlots_y, area_plots = standing.area$area_plots,
            nonreserved_acres = PROP_FOREST_TOTAL, green_ratio_used = green_ratio) %>%
  left_join(standing.support, by = 'species')
write.csv(standing, 'output/district_standing.csv', row.names = FALSE)

## growMort supplies the growth evaluation and annual factors, but neither it
## nor vitalRates returns both visits' DIA, HT and CR; pair TREE records below
## This vintage lacks SPCD in the midpoint table; recover it from the TREE key
if (!'SPCD' %in% names(db$TREE_GRM_MIDPT)) {
  db$TREE_GRM_MIDPT <- db$TREE_GRM_MIDPT %>%
    left_join(db$TREE %>% select(TRE_CN = CN, SPCD), by = 'TRE_CN')
}
growth <- growMort(db,
                   treeList = TRUE,
                   bySpecies = TRUE,
                   treeDomain = SPCD %in% spcd,
                   areaDomain = district_land)

## Keep the common growth-area denominator, including plots without target trees
growth.area <- growth %>%
  select(PLT_CN, EVAL_TYP, AREA_BASIS, CONDID, PROP_FOREST) %>%
  filter(!is.na(AREA_BASIS), PROP_FOREST > 0) %>%
  distinct()

## Calculate the same per-tree bough mass at both visits before pairing
endpoints <- db$TREE %>%
  filter(STATUSCD == 1, SPCD %in% spcd) %>%
  select(CN, PLT_CN, DIA, HT, CR, SPCD) %>%
  mutate(biomass(dbh = DIA, ht = HT, spcd = SPCD)) %>%
  mutate(crown_base = HT - CR / 100 * HT,
         p = if_else(CR == 0, 0,
           pmax(0, pmin(1, (HT * zone_fraction - crown_base) / (CR / 100 * HT)))),
         share = pmin(removal_cap, 1 - (1 - p)^3),
         boughs = if_else(HT > min_ht,
           (dry_foliage + dry_branches) * share * tonne_factor * green_ratio, 0),
         foliage_only = if_else(HT > min_ht,
           dry_foliage * share * tonne_factor * green_ratio, 0)) %>%
  select(CN, PLT_CN, DIA, HT, CR, boughs, foliage_only) %>%
  pivot_longer(c(boughs, foliage_only), names_to = 'quantity', values_to = 'bough_ton')

## Join current records, then each tree's previous record through PREV_TRE_CN
pairs <- growth %>%
  select(PLT_CN, EVAL_TYP, TREE_BASIS, SUBP, TREE, SPCD, COMMON_NAME,
         CURR_TPA, RECR_TPA, MORT_TPA, REMV_TPA) %>%
  filter(!is.na(TREE_BASIS), SPCD %in% spcd) %>%
  distinct() %>%
  left_join(db$TREE %>% select(PLT_CN, SUBP, TREE, CN, PREV_TRE_CN, STATUSCD),
            by = c('PLT_CN', 'SUBP', 'TREE')) %>%
  left_join(db$PLOT %>% select(PLT_CN = CN, PREV_PLT_CN, REMPER), by = 'PLT_CN') %>%
  filter(!is.na(PREV_PLT_CN), REMPER > 0) %>%
  cross_join(tibble(quantity = c('boughs', 'foliage_only'))) %>%
  left_join(endpoints %>% select(CN, quantity, current_mass = bough_ton),
            by = c('CN', 'quantity')) %>%
  left_join(endpoints %>% select(PREV_TRE_CN = CN, quantity, previous_plot = PLT_CN,
                                 previous_dia = DIA, previous_ht = HT,
                                 previous_cr = CR, previous_mass = bough_ton),
            by = c('PREV_TRE_CN', 'quantity')) %>%
  mutate(species = if_else(SPCD %in% c(20, 21, 22),
           'red fir (Shasta, California and noble)', COMMON_NAME),
         ingrowth = coalesce(RECR_TPA > 0, FALSE),
         survivor = coalesce(CURR_TPA > 0 & !ingrowth, FALSE),
         mortality = coalesce(MORT_TPA > 0, FALSE),
         removal = coalesce(REMV_TPA > 0, FALSE),
         linked = !is.na(previous_mass),
         excluded = (survivor | mortality | removal) & !linked)

## Split survivor gains and signed losses before aggregation; do not impute links
## Recruitment, mortality and removal factors are already annualized by FIA
changes <- pairs %>%
  mutate(survivor_change = if_else(survivor & linked,
           CURR_TPA * (current_mass - previous_mass) / REMPER, 0),
         survivor_accrual = pmax(survivor_change, 0),
         survivor_loss = pmin(survivor_change, 0),
         ingrowth = if_else(ingrowth, RECR_TPA * current_mass, 0),
         mortality = if_else(mortality & linked, MORT_TPA * previous_mass, 0),
         removals = if_else(removal & linked, REMV_TPA * previous_mass, 0),
         net_change = survivor_accrual + survivor_loss + ingrowth - mortality - removals) %>%
  pivot_longer(c(net_change, survivor_accrual, survivor_loss, mortality, ingrowth, removals),
               names_to = 'component', values_to = 'annual_ton')

## Estimate each annual component by species and material quantity
change_by_species <- customPSE(db,
                               x = changes,
                               xVars = annual_ton,
                               xGrpBy = c(species, quantity, component),
                               y = growth.area,
                               yVars = PROP_FOREST,
                               totals = TRUE)

## Estimate combined components with covariance between species
change_total <- customPSE(db,
                          x = changes,
                          xVars = annual_ton,
                          xGrpBy = c(quantity, component),
                          y = growth.area,
                          yVars = PROP_FOREST,
                          totals = TRUE)

## Count nonzero component plots and excluded links without adding species counts
support <- bind_rows(changes, changes %>% mutate(species = 'Combined')) %>%
  group_by(species, quantity, component) %>%
  summarise(component_plots = n_distinct(PLT_CN[annual_ton != 0]),
            excluded_unlinked = sum(excluded), .groups = 'drop')

## Save annual totals, per-acre rates, errors and plot support
change <- bind_rows(change_by_species, change_total %>% mutate(species = 'Combined')) %>%
  transmute(YEAR, species, quantity, component,
            green_tons_per_year = annual_ton_TOTAL, total_se_percent = annual_ton_SE,
            green_tons_acre_year = annual_ton_RATIO, per_acre_se_percent = annual_ton_RATIO_SE,
            total_se_tons_per_year = abs(annual_ton_TOTAL) * annual_ton_SE / 100,
            framework_species_plots = nPlots_x, area_plots = nPlots_y,
            nonreserved_acres = PROP_FOREST_TOTAL) %>%
  left_join(support, by = c('species', 'quantity', 'component'))
write.csv(change, 'output/district_change.csv', row.names = FALSE)

## Keep tree records local for reproducible validation; publish aggregate CSVs only
saveRDS(list(standing = tree.list, pairs = pairs, changes = changes, area = growth.area),
        'data/district_example.rds')
