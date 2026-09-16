## Author: Hunter Stanke
library(dplyr)
library(rFIA)

##=====
##  Parameters ----
##=====
fia_dir <- 'data/FIA'
state <- 'OR'
##=====
##  Latest completed inventory evaluation ----
##=====
## Which plot measurements belong to the latest published Oregon evaluation?
db <- readRDS(file.path(dirname(fia_dir), 'inventory.rds'))
recent <- clipFIA(db, mostRecent = TRUE)
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

print(years)
print(evals)
