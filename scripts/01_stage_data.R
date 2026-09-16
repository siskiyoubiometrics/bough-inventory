## Author: Hunter Stanke
library(dplyr)
library(rFIA)

##=====
##  Parameters ----
##=====
fia_dir <- 'data/FIA'
state <- 'OR'
tabs <- c('PLOT', 'PLOTGEOM', 'COND', 'TREE', 'POP_EVAL',
          'POP_EVAL_TYP', 'POP_EVAL_GRP', 'POP_PLOT_STRATUM_ASSGN')

##=====
##  Source vintage ----
##=====
## Which source files and file dates describe this Oregon inventory copy?
dir.create('output', showWarnings = FALSE)
files <- list.files(fia_dir, pattern = '^OR_.*[.]csv$', full.names = TRUE)
dates <- file.info(files)
vintage <- tibble(file = basename(files), bytes = dates$size,
                  modified_utc = format(dates$mtime, tz = 'UTC', usetz = TRUE)) %>%
  mutate(staged = file %in% paste0(state, '_', tabs, '.csv'))
write.csv(vintage, 'output/fia_vintage.csv', row.names = FALSE)
write.table(vintage, file.path(dirname(fia_dir), 'FIA_VINTAGE.txt'),
            sep = '\t', row.names = FALSE, quote = FALSE)

## Read the public fields needed to count plots and live trees.
db <- readFIA(fia_dir, states = state, tables = tabs)
db$PLOT <- db$PLOT %>%
  select(CN, PREV_PLT_CN, INVYR, STATECD, UNITCD, COUNTYCD, PLOT,
         PLOT_STATUS_CD, REMPER, INTENSITY, DESIGNCD, CYCLE, SUBCYCLE)
db$PLOTGEOM <- db$PLOTGEOM %>%
  select(CN, FVS_REGION, FVS_FOREST, FVS_DISTRICT)
db$COND <- db$COND %>%
  select(CN, PLT_CN, CONDID, COND_STATUS_CD, ADFORCD)
db$TREE <- db$TREE %>%
  select(CN, PLT_CN, CONDID, SPCD, STATUSCD, CR, HT)
saveRDS(db, file.path(dirname(fia_dir), 'inventory.rds'))
print(vintage)
