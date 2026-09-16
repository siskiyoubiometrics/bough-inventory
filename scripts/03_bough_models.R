## Author: Hunter Stanke
library(dplyr)
library(rFIA)
library(merchandiser)
library(tidyr)

##=====
##  Parameters ----
##=====
fia_dir <- 'data/FIA'
state <- 'OR'
sources <- read.csv('data/sources.csv')
forest_codes <- c(610)
forest_names <- tibble(code = c(610, 611),
  name = c('Rogue River portion', 'Siskiyou portion'))
forest_name <- forest_names %>% filter(code %in% forest_codes)
coverage <- paste0(paste(forest_name$name, collapse = ' and '),
  ' of the Rogue River-Siskiyou National Forest (administrative forest code ',
  paste(forest_codes, collapse = ', '), ')')
reserved <- as.numeric(sources$value[sources$id == 'reserved'])
district <- NA
min_ht <- as.numeric(sources$value[sources$id == 'min_ht'])
reach_ft <- 15
## Read fractions written as numerator/denominator in the source ledger.
fraction_values <- sources %>%
  filter(id %in% c('zone_fraction', 'removal_cap')) %>%
  separate_wider_delim(value, delim = '/', names = c('numerator', 'denominator')) %>%
  mutate(fraction = as.numeric(numerator) / as.numeric(denominator))
zone_fraction <- fraction_values$fraction[fraction_values$id == 'zone_fraction']
removal_cap <- fraction_values$fraction[fraction_values$id == 'removal_cap']
allocation <- 'cone'  ## Choose 'cone' or 'linear'.
if (!allocation %in% c('cone', 'linear')) stop('Choose cone or linear allocation.')
division <- 0  ## National NSVB coefficients; no assumed local ecodivision.
green_dry <- as.numeric(sources$value[sources$id == 'green_dry'])
green_moderate <- as.numeric(sources$value[sources$id == 'green_moderate'])
green_wet <- as.numeric(sources$value[sources$id == 'green_wet'])
green_ratio <- green_moderate
kg_per_lb <- 0.45359237  ## Exact unit definition, not a fitted parameter.
lb_per_ton <- 2000  ## US short ton throughout the outputs.
spcd <- c(21, 20, 81, 119, 22, 15, 202, 122)
spp <- tibble(SPCD = spcd,
  species = c('red fir (Shasta, California and noble)',
              'red fir (Shasta, California and noble)', 'Incense-cedar',
              'Western white pine', 'red fir (Shasta, California and noble)',
              'White fir', 'Douglas-fir', 'Ponderosa pine'))
tabs <- c('PLOT', 'PLOTGEOM', 'COND', 'TREE', 'POP_EVAL', 'POP_EVAL_TYP',
          'POP_EVAL_GRP', 'POP_PLOT_STRATUM_ASSGN', 'POP_ESTN_UNIT',
          'POP_STRATUM', 'TREE_GRM_COMPONENT', 'TREE_GRM_BEGIN',
          'TREE_GRM_MIDPT', 'SUBP_COND_CHNG_MTRX')

##=====
##  Evaluation and land selection ----
##=====
## Read the full sampling design to estimate forest resources.
db <- readFIA(fia_dir, states = state, tables = tabs, nCores = 1)
db <- clipFIA(db, mostRecent = TRUE)
## Keep only FIA fields used below; do not reuse added source analysis columns.
db$TREE <- db$TREE %>%
  select(CN, PLT_CN, PREV_TRE_CN, CONDID, PREVCOND, SUBP, TREE,
         SPCD, STATUSCD, DIA, HT, CR, TPA_UNADJ, TREECLCD)
## Reserved status covers wilderness and other reserved designations.
## Excluding all reserved forest is a conservative exclusion.
db$COND <- db$COND %>%
  mutate(bough_land = coalesce(COND_STATUS_CD == 1 & ADFORCD %in% forest_codes &
                                RESERVCD == reserved, FALSE))
if (!is.na(district)) {
  if (!any(db$PLOTGEOM$FVS_DISTRICT == district, na.rm = TRUE)) {
    stop('District has no populated assignments in this release.')
  }
  district_plots <- db$PLOTGEOM %>%
    filter(FVS_DISTRICT == district) %>% pull(CN)
  db$COND$bough_land <- db$COND$bough_land &
    db$COND$PLT_CN %in% district_plots
}

##=====
##  Crown components and harvestable fractions ----
##=====
## What does NSVB predict for each live target tree, including previous visits?
trees <- db$TREE %>% filter(STATUSCD == 1, SPCD %in% spcd)
mass <- biomass(dbh = trees$DIA, ht = trees$HT,
                spcd = trees$SPCD, division = division)
## Compare identical illustrative trees under the two source species codes.
## These dimensions are test inputs, not observations or sourced coefficients.
check_trees <- tibble(dbh_inches = c(10, 20, 30), height_ft = c(40, 80, 120))
shasta <- biomass(check_trees$dbh_inches, check_trees$height_ft,
                  rep(21, nrow(check_trees)), division = division)
noble <- biomass(check_trees$dbh_inches, check_trees$height_ft,
                 rep(22, nrow(check_trees)), division = division)
check <- check_trees %>%
  mutate(species = 'red fir (Shasta, California and noble)',
         shasta_foliage_tonnes = shasta$dry_foliage,
         noble_foliage_tonnes = noble$dry_foliage,
         shasta_branches_tonnes = shasta$dry_branches,
         noble_branches_tonnes = noble$dry_branches,
         foliage_identical = shasta_foliage_tonnes == noble_foliage_tonnes,
         branches_identical = shasta_branches_tonnes == noble_branches_tonnes,
         package_version = as.character(packageVersion('merchandiser')))
write.csv(check, 'output/crown_component_check.csv', row.names = FALSE)
trees <- trees %>%
  mutate(foliage_lb = mass$dry_foliage * 1000 / kg_per_lb,
         branches_lb = mass$dry_branches * 1000 / kg_per_lb,
         crown_length = HT * CR / 100,
         crown_base = HT * (1 - CR / 100),
         zone_top = HT * zone_fraction,
         reach_top = pmin(zone_top, reach_ft),
         rule_p = if_else(CR == 0, 0,
           pmax(0, pmin(1, (zone_top - crown_base) / crown_length))),
         reach_p = if_else(CR == 0, 0,
           pmax(0, pmin(1, (reach_top - crown_base) / crown_length))),
         rule_share = if (allocation == 'cone') 1 - (1 - rule_p)^3 else rule_p,
         reach_share = if (allocation == 'cone') 1 - (1 - reach_p)^3 else reach_p,
         rule_fraction = pmin(removal_cap, rule_share),
         reach_fraction = pmin(removal_cap, reach_share),
         linear_rule_fraction = pmin(removal_cap, rule_p),
         linear_reach_fraction = pmin(removal_cap, reach_p),
         eligible = HT > min_ht,
         rule_boughs = if_else(eligible,
           (foliage_lb + branches_lb) * rule_fraction, 0),
         rule_foliage_only = if_else(eligible, foliage_lb * rule_fraction, 0),
         reach_boughs = if_else(eligible,
           (foliage_lb + branches_lb) * reach_fraction, 0),
         reach_foliage_only = if_else(eligible, foliage_lb * reach_fraction, 0),
         full_crown = if_else(eligible, foliage_lb + branches_lb, 0),
         linear_rule_boughs = if_else(eligible,
           (foliage_lb + branches_lb) * linear_rule_fraction, 0),
         linear_rule_foliage_only = if_else(eligible, foliage_lb * linear_rule_fraction, 0),
         linear_reach_boughs = if_else(eligible,
           (foliage_lb + branches_lb) * linear_reach_fraction, 0),
         linear_reach_foliage_only = if_else(eligible, foliage_lb * linear_reach_fraction, 0))
## The crown is a cone with uniform biomass density, apex at the tree top.
## Crown width cancels in the volume ratio, so no crown width is needed.
## CR is compacted crown ratio, used as a continuous crown-length proxy.
## boughs is the primary harvestable quantity: foliage plus branch wood, cut to the bole.
## foliage_only is the secondary quantity describing a tip-cutting harvest.
## The noble-fir green/dry ratio applies to all target species.
conversion <- green_ratio / lb_per_ton
trees <- trees %>%
  mutate(rule_boughs = rule_boughs * conversion,
         rule_foliage_only = rule_foliage_only * conversion,
         reach_boughs = reach_boughs * conversion,
         reach_foliage_only = reach_foliage_only * conversion,
         full_crown = full_crown * conversion,
         linear_rule_boughs = linear_rule_boughs * conversion,
         linear_rule_foliage_only = linear_rule_foliage_only * conversion,
         linear_reach_boughs = linear_reach_boughs * conversion,
         linear_reach_foliage_only = linear_reach_foliage_only * conversion) %>%
  left_join(spp, by = 'SPCD')

## Audit only current visits in the actual standing tree list and land domain.
current_list <- tpa(db, landType = 'forest', treeType = 'live',
  treeDomain = SPCD %in% spcd & HT > min_ht,
  areaDomain = bough_land, treeList = TRUE)
current_keys <- current_list %>%
  filter(!is.na(TREE_BASIS), TPA > 0) %>% distinct(PLT_CN, SUBP, TREE)
quality <- trees %>%
  semi_join(current_keys, by = c('PLT_CN', 'SUBP', 'TREE')) %>%
  group_by(species) %>%
  summarise(records = n(), missing_mass = sum(is.na(rule_boughs)),
            invalid_crown = sum(is.na(CR) | CR < 0 | CR > 100),
            .groups = 'drop')
if (any(quality$missing_mass > 0 | quality$invalid_crown > 0)) {
  stop('Current estimation population has missing or invalid crown inputs.')
}
if (any(trees$reach_boughs > trees$rule_boughs, na.rm = TRUE)) {
  stop('Reach mass exceeds rule mass.')
}
if (any(trees$rule_foliage_only > trees$rule_boughs, na.rm = TRUE)) {
  stop('foliage_only mass exceeds boughs mass.')
}
settings <- list(fia_dir = fia_dir, state = state, forest_codes = forest_codes,
                 coverage = coverage,
                 district = district, min_ht = min_ht, reach_ft = reach_ft,
                 green_ratio = green_ratio, green_dry = green_dry,
                 green_wet = green_wet, division = division,
                 allocation = allocation, zone_fraction = zone_fraction,
                 removal_cap = removal_cap)
saveRDS(list(db = db, trees = trees, spp = spp, settings = settings),
        file.path(dirname(fia_dir), 'bough_models.rds'))
print(check)
print(quality)
