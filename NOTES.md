# Methods

Hunter Stanke

## Data

The analysis uses a January 2022 public copy of the Forest Inventory and Analysis database (FIADB) for Oregon. The [vintage record](output/fia_vintage.csv) lists source filenames and modification dates, which describe the local copy rather than tree measurement dates or a certified release date. Some source tables contain added analysis columns, so the forest calculations retain the named inventory fields they need. The copy is not represented as byte-identical to an original download.

Forest location, land status, and tree measurements enter the analysis through separate tables. `PLOT` supplies visits, measurement intervals, previous-plot links, and ecoregion codes. `PLOTGEOM` supplies administrative forest and district assignments. `COND` identifies forest land, administrative forest codes, reserved status, and the condition shares used to estimate area. `TREE` supplies species, live status, dimensions, crown ratio, and links to previous tree records. The population and growth tables supply the sampling design and annual change factors.

The Forest Inventory and Analysis (FIA) program assigns administrative district codes from exact plot locations when those codes are present. The district field is empty throughout this copy, so a district name lookup cannot recover the missing assignments. The district example instead uses ecoregion codes assigned from fuzzed and swapped public coordinates. That proxy approximates a district and carries boundary uncertainty beyond the reported sampling error.

To refresh the analysis, download one coherent Oregon release into an empty local directory using the command in `scripts/00_download.R`, set the same `fia_dir` in scripts 01 through 06, and run scripts 01 through 07. Check the new evaluation dates and district availability before interpreting the replacement results. The numbered scripts regenerate all published outputs, and raw tables and per-tree files remain local.

## Domain

The forest estimates cover nonreserved forest conditions in the Oregon part of the Rogue River portion of the Rogue River-Siskiyou National Forest. Script 03 selects administrative forest code 610 and excludes code 611, the Siskiyou portion. Reserved land is excluded because reserved status includes wilderness and other designations that restrict the land base considered for harvest. Excluding all reserved land is conservative because it removes every reserved condition without assuming that a particular designation allows bough collection. Nonreserved status alone does not establish access or permission to harvest.

The forest estimates use condition-level administrative assignments, while the unweighted counts in script 02 use the plot-level Region 6, Forest 10 assignment. Those counts describe a different selection from the plots supporting the estimates. Script 06 uses the plot-level forest code and Cascades ecoregion subsections for the High Cascades proxy, so its estimates are not an exact subdivision of the condition-level forest totals. Previous forest assignments are retained before the inventory is clipped to its latest evaluation, allowing change calculations to use the recorded domain at both visits.

## Trees and the harvest zone

The modeled harvest pool includes live target trees taller than 15 feet and the live crown within the lower third of total tree height. Crown length is total height multiplied by the recorded compacted crown ratio, and crown base is total height minus that length. The compacted ratio represents a continuous crown in this analysis. A zero crown ratio gives zero harvestable mass. The reach scenario further limits the top of the harvest zone to 15 feet above ground.

The crown is represented as a cone with its apex at the tree top and its base at the live crown base. If `p` is the fraction of crown length within the harvest zone, bounded between zero and one, the corresponding volume fraction is `1 - (1 - p)^3`. Crown width cancels in the ratio of the lower cone segment to the whole cone, so no crown width estimate is needed. Uniform biomass density converts that volume fraction to a mass fraction. The linear sensitivity uses `p` instead and holds the sample and crown masses fixed.

The applied fraction is the smaller of the geometric fraction and the one-third foliage cap. The same one-third cap is applied to branch mass as an assumption of uniform crown density. The primary bough quantity includes foliage and branch wood cut to the bole, matching the whole-branch interpretation of the permit terms. Foliage alone is a secondary quantity for a tip-cutting interpretation, and the model does not distinguish terminal tips or marketable quality.

The assumed vertical distribution gives lower branches more wood per unit foliage than the crown average. Under that assumption, the uniform-density cone is conservative for total green weight and mildly optimistic for foliage alone. No measured vertical profile for these species enters the calculations, so this direction is a qualitative interpretation rather than a fitted correction.

## Crown biomass

Crown mass is estimated from diameter, height, and recorded species using the National Scale Volume and Biomass equations through the merchandiser package. Script 03 selects national coefficients with `division = 0`, and script 06 uses the same national default. Diameter is supplied in inches and height in feet, and the package returns dry component mass in metric tonnes. No additional broken-top adjustment is applied. The equation reference and component tables are recorded under `nsvb` in the [source ledger](data/sources.csv).

Shasta red fir code 21 and noble fir code 22 share the group-3 branch and foliage coefficients. Shared coefficients do not imply equal final branch mass because the branch calculation also uses species wood density and component harmonization. The [paired component check](output/crown_component_check.csv) gives equal foliage but different branch mass for matching illustrative dimensions. These dimensions are comparison inputs, not sampled trees.

Codes 20, 21, and 22 are combined as red fir (Shasta, California and noble) to report the related fir forms together without making the resource estimate depend on their separation in field coding. Each tree retains its recorded species code for crown prediction, and the codes are merged before estimating population totals and errors. The combined error therefore includes covariance within the reporting group.

Green weight is dry mass multiplied by 2.42, the moderate-moisture noble fir conversion reported by [Blatner and colleagues (2005)](https://research.fs.usda.gov/download/treesearch/24847.pdf), with alternatives of 2.27 and 2.54 retained in the source ledger. Applying that conversion to every species and to both foliage and branches is an analysis assumption. Metric tonnes are converted using the exact definitions of 1,000 kilograms per tonne, 0.45359237 kilograms per pound, and 2,000 pounds per US short ton.

## Estimation

Population totals and per-acre estimates use rFIA and its temporally indifferent estimator with the most recent completed evaluation in the downloaded tables. Selection follows evaluation membership rather than a simple measurement-year filter. Standing and change use their own sampling bases and area denominators, including forest area on plots without target trees. Species errors are calculated after grouping trees, and combined errors retain covariance between species.

<!-- support:start -->

The most recent reporting year is 2019. The forest standing sample includes 265 domain plots, and the change sample includes 234 remeasured domain plots. The forest change calculation excludes 15 tree records with missing required previous measurements.

The district proxy includes 184 standing domain plots and 168 remeasured domain plots. It has 182 plots with eligible target trees and excludes 10 tree records from affected change components because required previous measurements are missing.

<!-- support:end -->

Plot counts measure sample support rather than resource abundance, access, or bough quality. Species can occur on the same plot, so their plot counts cannot be added. The [plot support table](output/plot_counts.csv) distinguishes eligible trees, positive standing mass, linked survivors, and nonzero change.

Sampling error is the estimated standard error expressed as a percentage of the absolute estimate. It describes variation from the inventory sampling design and excludes uncertainty from crown equations, crown shape, moisture conversion, missing previous measurements, and proxy boundaries. Relative error is undefined for a zero estimate. The independent whole-crown expansion in script 04 checks population expansion and unit conversion using the same crown inputs, without independently validating the biomass equations.

## Change on remeasured plots

Annual change follows the same trees between visits, using each visit's own diameter, height, and crown ratio. Previous tree links are checked against the previous plot, and survivor mass differences are divided by the recorded measurement interval. The inventory recruitment, mortality, and removal factors are already annualized. They are not divided by that interval again.

- Gross accrual sums positive annual changes in modeled harvestable mass on surviving trees.
- Survivor loss sums negative annual changes on surviving trees and retains their negative sign.
- Ingrowth adds current eligible mass using the annual recruitment factor for trees entering the inventory framework.
- Mortality subtracts previous eligible mass using the annual mortality factor and omits unobserved growth before death.
- Removals subtract previous eligible mass using the annual removal factor and omit unobserved growth before removal.
- Net change adds gross accrual, signed survivor loss, and ingrowth, then subtracts mortality and removals.

Crown recession can reduce the harvestable pool as a stand develops without disturbance. In dense stands, lower branches die as light becomes limited, and the live crown base can rise faster than the boundary at one third of total tree height. A surviving tree can therefore gain height while losing material from the lower-third harvest zone. The calculations capture the resulting endpoint change but do not identify the cause of each observed loss.

Positive and negative survivor changes are separated before aggregation, so gains on one tree do not conceal losses on another. Surviving trees that cross the height threshold enter through their own endpoint change. Trees lacking required previous measurements are excluded from the affected components, and net change is consequently a subtotal of observed components. Sampling error does not compensate for missing links. Neither gross accrual nor net change measures recovery after bough cutting or establishes a reharvest interval.

## Reading the results

Net change is not distinguishable from zero wherever its sampling error exceeds 100 percent. The following rows meet that condition for either their total or per-acre estimate, using unrounded errors. The forest reach rows refer to the additional 15-foot reach limit, and the district proxy uses only the lower-third height zone.

<!-- uncertain:start -->

|Domain              |Zone        |Species                                |Material     |Total error (%) |Per-acre error (%) |
|:-------------------|:-----------|:--------------------------------------|:------------|:---------------|:------------------|
|Forest              |Lower third |Incense-cedar                          |Boughs       |328.8*          |328.8*             |
|Forest              |Lower third |Incense-cedar                          |Foliage only |331.4*          |331.4*             |
|Forest              |Lower third |Ponderosa pine                         |Boughs       |414.1*          |414.1*             |
|Forest              |Lower third |Ponderosa pine                         |Foliage only |285.1*          |285.0*             |
|Forest              |Lower third |Western white pine                     |Boughs       |100.5*          |100.3*             |
|Forest              |Lower third |Western white pine                     |Foliage only |307.2*          |307.0*             |
|Forest              |Lower third |White fir                              |Boughs       |107.9*          |107.8*             |
|Forest              |Lower third |White fir                              |Foliage only |126.8*          |126.8*             |
|Forest              |Lower third |Combined                               |Foliage only |147.8*          |147.8*             |
|Forest              |Reach limit |Douglas-fir                            |Boughs       |106.7*          |106.6*             |
|Forest              |Reach limit |Douglas-fir                            |Foliage only |134.1*          |134.0*             |
|Forest              |Reach limit |Incense-cedar                          |Boughs       |356.3*          |356.2*             |
|Forest              |Reach limit |Incense-cedar                          |Foliage only |284.1*          |284.0*             |
|Forest              |Reach limit |White fir                              |Boughs       |202.3*          |202.3*             |
|Forest              |Reach limit |White fir                              |Foliage only |161.6*          |161.5*             |
|Forest              |Reach limit |red fir (Shasta, California and noble) |Boughs       |136.3*          |136.1*             |
|Forest              |Reach limit |red fir (Shasta, California and noble) |Foliage only |104.5*          |104.3*             |
|Forest              |Reach limit |Combined                               |Boughs       |363.7*          |363.7*             |
|Forest              |Reach limit |Combined                               |Foliage only |212.5*          |212.5*             |
|High Cascades proxy |Lower third |Ponderosa pine                         |Boughs       |246.7*          |246.8*             |
|High Cascades proxy |Lower third |Ponderosa pine                         |Foliage only |193.9*          |194.0*             |
|High Cascades proxy |Lower third |Western white pine                     |Boughs       |350.4*          |350.3*             |
|High Cascades proxy |Lower third |White fir                              |Boughs       |171.7*          |172.9*             |
|High Cascades proxy |Lower third |White fir                              |Foliage only |168.9*          |170.1*             |
|High Cascades proxy |Lower third |Combined                               |Boughs       |806.7*          |805.3*             |
|High Cascades proxy |Lower third |Combined                               |Foliage only |458.7*          |457.3*             |

<!-- uncertain:end -->

For these rows, the sign of the estimated net balance does not establish an increase or decline in the harvestable pool. Large positive accrual can coexist with a net change near zero because survivor loss, mortality, and removals offset gains. The component estimates describe those observed contributions, but neither a flagged net balance nor an error below the flag threshold establishes a sustainable cutting rate. Rows below the threshold still require an uncertainty assessment for any claim of change, and sample zeros do not establish absence of a resource.

## Limits

The January 2022 copy supports an evaluation ending in 2019 and does not measure current forest conditions. A refreshed inventory can change the sample, district assignments, standing resource, and measured change. Oregon coverage also leaves any California land outside the analysis.

The published noble fir bough model cannot run on these inventory trees because it requires unrecorded whorl ages, cuttings per whorl, and neighborhood information. Its harvest zone also differs from the lower-third rule. The equation remains in the ledger and its prediction is missing, without substituting assumed field measurements. The separate zero-to-whole-crown range in the standing output is a physical mass envelope, not a prediction from that model or an uncertainty interval.

The missing district code prevents an exact administrative district estimate from this vintage. Ecoregion proxies support approximate comparisons, with boundary uncertainty outside the sampling error. Species represented on few plots have less support, especially for rare mortality and removal events. Their component estimates and plot counts must be read together, and the model does not resolve access, market quality, or recovery following harvest.
