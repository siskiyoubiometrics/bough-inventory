# Methods

Hunter Stanke

## Data and domain

The analysis estimates the High Cascades Ranger District of the Rogue River-Siskiyou National Forest through an ecoregion proxy on nonreserved forest land.

The public Oregon inventory copy dates from January 2022, and the [vintage record](output/fia_vintage.csv) lists its source filenames and modification dates.

File dates describe the local copy rather than tree measurement dates or a certified release date.

Some source tables contain added columns, so the analysis retains the named inventory fields needed for tree calculations.

The copy is not represented as byte-identical to an original download.

`PLOT` supplies visits, measurement intervals, previous-plot links and ecoregion codes.

`PLOTGEOM` supplies administrative forest and district assignments.

`COND` identifies forest land, reserved status and the condition shares used to estimate area.

`TREE` supplies species, live status, dimensions, crown ratio and links to previous tree records.

The population and growth tables supply the sampling design and annual change factors.

Script 03 selects plots with `FVS_LOC_CD` in `forest_codes`, joins `PLOT.ECOSUBCD` onto `COND`, and retains forest conditions with `RESERVCD == 0` in the selected subsections.

The default proxy uses code 610 with `M242Bb`, `M242Be`, `M242Bg` and `M261Dh`.

Both visits' administrative assignments are retained before clipping to the latest evaluation so the change calculation uses the recorded domain at each visit.

The Forest Inventory and Analysis program assigns administrative district codes from exact plot locations, but `FVS_DISTRICT` is empty in this copy.

Ecoregion codes assigned from fuzzed and swapped public coordinates approximate the district boundary and add uncertainty beyond the sampling error.

Nonreserved status excludes all reserved designations and does not establish access for bough collection.

The README describes the three domain settings in script 03.

To refresh the analysis, place one coherent Oregon release in `data/FIA`, check the new evaluation dates and district availability, and run scripts 01 through 07.

Raw tables and per-tree files remain local.

## Trees and the harvest zone

The modeled harvest pool includes live target trees taller than 15 feet and the live crown within the lower third of total height.

Crown length is total height multiplied by the recorded compacted crown ratio, which represents a continuous crown in this analysis.

Crown base is total height minus crown length.

A zero crown ratio gives zero harvestable mass.

The reach scenario further limits the top of the harvest zone to 15 feet above ground.

The crown is a cone with its apex at the tree top and its base at the live crown base.

For the fraction `p` of crown length within the harvest zone, bounded between zero and one, the corresponding volume fraction is `1 - (1 - p)^3`.

Crown width cancels in the volume ratio.

Uniform biomass density converts the volume fraction to a mass fraction.

The linear sensitivity uses `p` while holding the sample and crown masses fixed.

The applied fraction is the smaller of the geometric fraction and the one-third foliage cap.

The same fraction is applied to branch mass under the uniform-density assumption.

The primary bough quantity includes foliage and branch wood cut to the bole.

Foliage alone is a secondary quantity that does not distinguish terminal tips or marketable quality.

The assumed vertical distribution gives lower branches more wood per unit foliage than the crown average, making the uniform-density cone conservative for total weight and mildly optimistic for foliage alone.

No measured vertical profile enters the calculations, so that direction is a qualitative interpretation.

## Crown biomass and reporting groups

Crown mass is estimated from diameter, height and recorded species using the National Scale Volume and Biomass equations through merchandiser.

Script 03 selects national coefficients with `division = 0`.

Diameter is supplied in inches and height in feet, and the package returns dry component mass in metric tonnes.

No additional broken-top adjustment is applied.

The equation reference and component tables appear under `nsvb` in the [source ledger](data/sources.csv).

Shasta red fir code 21 and noble fir code 22 share the group-3 branch and foliage coefficients.

Shared coefficients do not imply equal final branch mass because the branch calculation also uses species wood density and component harmonization.

The [paired component check](output/crown_component_check.csv) gives equal foliage but different branch mass for matching illustrative dimensions, which are comparison inputs rather than sampled trees.

Codes 20, 21 and 22 are reported as Shasta red fir (with California and noble) because these related firs hybridize and crews code them inconsistently.

Codes 15 and 17 are reported as white and grand fir for the same reason.

Each tree retains its recorded code for crown prediction, and grouping occurs before population estimation so errors retain covariance within each fir group.

The other reporting groups are incense-cedar (81), western white pine (119), Douglas-fir (202) and ponderosa pine (122).

Green weight is dry mass multiplied by 2.42, the moderate-moisture noble fir conversion reported by [Blatner and colleagues (2005)](https://research.fs.usda.gov/download/treesearch/24847.pdf).

Applying that conversion to every species and to both foliage and branches is an analysis assumption.

Alternative conversion factors of 2.27 and 2.54 remain in the source ledger.

Metric tonnes are converted using the exact definitions of 1,000 kilograms per tonne, 0.45359237 kilograms per pound and 2,000 pounds per US short ton.

## Estimation and intervals

Population totals and per-acre estimates use the rFIA temporally indifferent estimator with the most recent completed evaluation in the downloaded tables.

Selection follows evaluation membership rather than a measurement-year filter.

Standing and change use their own sampling bases and common nonreserved-area denominators, including plots without target trees.

Each condition appears once in its area denominator.

Combined errors are estimated from all target trees together and retain covariance between reporting groups.

<!-- support:start -->

The most recent reporting year is 2019.

The standing sample contains 184 domain plots, including 182 plots with eligible target trees.

The change sample contains 168 remeasured domain plots.

The change calculation excludes 10 tree records from affected components because required previous measurements are missing.

<!-- support:end -->

Species plot counts include distinct plots with live target trees taller than 15 feet, including eligible trees whose modeled harvest-zone mass is zero.

Species can share plots, so their plot counts cannot be added.

The [plot support table](output/plot_counts.csv) distinguishes eligible trees, positive standing mass, linked survivors and excluded records.

Sampling error is the estimated standard error expressed as a percentage of the absolute estimate, and is undefined for a zero estimate.

The standing 95 percent interval is the total plus or minus `qt(0.975, n - 1)` times its standard error, where `n` is the number of distinct area plots in the domain estimation unit, including plots without eligible target trees.

Intervals retain their calculated endpoints without truncation at zero.

Sampling error excludes uncertainty from crown equations, crown shape, moisture conversion, missing previous measurements and proxy boundaries.

The independent whole-crown expansion in script 04 checks population expansion and unit conversion using the same crown inputs without independently validating the biomass equations.

## Change on remeasured plots

Annual change follows the same trees between visits using each visit's own diameter, height and crown ratio.

Previous tree links are checked against the previous plot.

Survivor mass differences are divided by the recorded measurement interval.

The inventory recruitment, mortality and removal factors are already annualized and are not divided by that interval again.

| Component | Calculation |
| --- | --- |
| Gross accrual | Sum positive annual changes in modeled harvestable mass on surviving trees. |
| Survivor loss | Sum negative annual changes on surviving trees with their negative sign. |
| Ingrowth | Add current eligible mass using the annual recruitment factor. |
| Mortality | Subtract previous eligible mass using the annual mortality factor. |
| Removals | Subtract previous eligible mass using the annual removal factor. |
| Net change | Add gross accrual, signed survivor loss and ingrowth, then subtract mortality and removals. |

Mortality and removals appear as positive losses in the tables.

Loss estimates omit unobserved growth before death or removal.

Crown recession can reduce the modeled harvestable pool when the live crown base rises faster than the boundary at one third of total height.

The calculations capture endpoint change without identifying the cause of each loss.

Positive and negative survivor changes are separated before aggregation so gains on one tree do not conceal losses on another.

Surviving trees that cross the height threshold enter through their own endpoint change.

Trees lacking required previous measurements are excluded from affected components, so net change is a subtotal of observed components.

Sampling error does not compensate for missing links.

Neither gross accrual nor net change measures recovery after bough cutting or establishes a reharvest interval.

## Reading the results

The **not distinguishable from zero** flag applies wherever the unrounded total or per-acre sampling error exceeds 100 percent.

The following net-change rows meet that rule, including the additional 15-foot reach scenario.

<!-- uncertain:start -->

|Zone        |Species                                    |Material     |Total error (%) |Per-acre error (%) |
|:-----------|:------------------------------------------|:------------|:---------------|:------------------|
|Lower third |Ponderosa pine                             |Boughs       |246.7*          |246.8*             |
|Lower third |Ponderosa pine                             |Foliage only |193.9*          |194.0*             |
|Lower third |Western white pine                         |Boughs       |350.4*          |350.3*             |
|Lower third |White and grand fir                        |Boughs       |846.2*          |847.5*             |
|Lower third |White and grand fir                        |Foliage only |584.6*          |585.9*             |
|Lower third |Combined                                   |Boughs       |319.6*          |318.1*             |
|Lower third |Combined                                   |Foliage only |247.4*          |245.9*             |
|Reach limit |Douglas-fir                                |Boughs       |445.4*          |446.1*             |
|Reach limit |Douglas-fir                                |Foliage only |6906.9*         |6907.7*            |
|Reach limit |Ponderosa pine                             |Boughs       |106.6*          |106.6*             |
|Reach limit |Shasta red fir (with California and noble) |Boughs       |202.9*          |202.8*             |
|Reach limit |Shasta red fir (with California and noble) |Foliage only |154.8*          |154.7*             |
|Reach limit |White and grand fir                        |Boughs       |125.4*          |123.8*             |
|Reach limit |White and grand fir                        |Foliage only |132.5*          |130.9*             |

<!-- uncertain:end -->

The sign of a flagged net balance does not establish an increase or decline in the harvestable pool.

Positive accrual can coexist with net change near zero because survivor loss, mortality and removals offset gains.

An error below the flag threshold does not establish statistical significance or a sustainable cutting rate.

Sample zeros do not establish absence of a resource.

## Limits

The evaluation ending in 2019 does not measure current forest conditions.

A refreshed inventory can change the sample, district assignments, standing resource and measured change.

Oregon coverage leaves any California land outside the analysis.

The published noble fir bough model requires unrecorded whorl ages, cuttings per whorl and neighborhood information, so its prediction is unavailable for these inventory trees.

Its equation remains in the ledger without substituting assumed measurements.

The missing district code prevents an exact administrative district estimate from this vintage.

Species represented on few plots have less support, especially for rare mortality and removal events.

The model does not resolve access, market quality or recovery following harvest.
