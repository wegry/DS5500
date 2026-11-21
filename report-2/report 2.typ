
// Optimizing Corporate Decarbonization Investments
// Expanded from Konstantinos Theodoropoulos' solo pitch (DS5500, Fall 2026).
// Build: typst compile proposal.typ

#import "@preview/charged-ieee:0.1.4": ieee
#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node

// Red placeholder so unfinished rubric sections stand out in the PDF.
#let todo(body) = text(fill: red)[*TODO:* #body]
#set page(numbering: "1")

// ---- 1 & 2: name and title ------------------------------------------------

#show: ieee.with(
  title: [Optimizing Decarbonization Investment Decisions for Boston Office Buildings],
  // One combined entry keeps the author block to two short lines instead of
  // a full column per author. PDF metadata is set separately below.
  authors: (
    (
      name: "Konstantinos Theodoropoulos, Zachary Wegrzyniak, and Kateryna Lysytsyna",
      department: [
        DS5500 Data Science Capstone, Northeastern University \
        #link("https://github.com/wegry/DS5500")[github.com/wegry/DS5500] \
        Sponsor: Konstantinos Theodoropoulos
      ],
    ),
  ),
  abstract: [Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) requires large buildings to meet increasingly strict greenhouse gas emissions limits, with a major compliance milestone in 2030. This project aims to identify cost-effective decarbonization options for Boston office buildings by considering BERDO disclosures, ComStock building simulations, and Buildings Technology Baseline (BTB) installation cost data. The integrated analysis includes 297 matched office buildings, 81 of which exceed the 2030 emissions standard under BERDO's projected 2030 electricity emissions factor. A data integration pipeline was developed to match BERDO buildings with representative ComStock simulations and estimate potential retrofit emissions reductions. Installation costs, energy bills, and Alternative Compliance Payments (ACP) are combined to select one of thirteen retrofit options or ACPs over the 2030-2034 period, complemented by a 20-year life-cycle cost and Monte Carlo uncertainty analysis. The resulting framework aims to support investment decisions for office buildings by balancing emissions reductions, compliance requirements, and budget constraints.
  ],
  index-terms: (
    "Building decarbonization",
    "BERDO",
    "Retrofit optimization",
    "Office buildings",
    "Emissions compliance",
  ),
  // Placed manually at the end of the body so the appendix can follow it.
  bibliography: none,
)

#set document(author: (
  "Konstantinos Theodoropoulos",
  "Zachary Wegrzyniak",
  "Kateryna Lysytsyna",
))


// ---- 3: goal / outcome ----------------------------------------------------

= Introduction

How can municipalities work to decarbonize? Part of Boston's approach is to give a financial reason for building owners to cut emissions. Under Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO), residential buildings with 15 or more units and nonresidential
buildings of 20,000 sq ft or more have to report their energy use
every year and meet emissions limits that step down over time, reaching net
zero by 2050 (@fig:berdo-limits) @berdo. The owner of one of these buildings, say an office, has a list of candidate
projects: heat pumps, envelope upgrades, LED retrofits, rooftop solar,
switching off fuel oil, etc. If a retrofit is not economical, the owner can instead make an _Alternative Compliance Payment_ (ACP). Are ACPs a strong enough incentive to drive decarbonization?

Owners might lack the capital to do all of the updates at once,
so somebody has to pick an order. The standard tool for that is a marginal
abatement cost curve (MACC), which ranks projects by dollars per ton of
CO#sub[2] avoided and funds them from the cheapest on down.

That ranking treats every project as independent and every year as the same.
Neither is true. A heat pump in a building that was just insulated saves less
than the two estimates added together. And under BERDO, _when_ a building gets
under its limit matters as much as _whether_ it does, since each building has
its own first compliance year and the limits keep tightening after that.

Our goal is to develop a decision-support tool that helps building owners in Boston determine which decarbonization projects to implement and when (@fig:pipeline). MACC will serve as our baseline. Rather than simply ranking projects individually, the current implementation compares building-level retrofit decisions for 2030-2034. A budget-constrained, multi-year investment roadmap remains a proposed extension.

= Methods

== Data

This project uses three publicly available data sources: Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) disclosures, National Lab of the Rockies (NLR) ComStock, and the NLR 2024 Buildings Technology Baseline (BTB).

*BERDO* provides building-level information, including property type, gross floor area, energy consumption by fuel, and greenhouse gas emissions @berdo. The analysis focuses on Boston office buildings because these buildings have a relatively high emissions reporting rate. Records are prepared using dbt to standardize property types for storage in DuckDB, convert the fuels BERDO reports in kBtu (natural gas, district energy, and oil/propane) to kWh to match electricity, aggregate related fuel categories, and identify missing or inconsistent values. BERDO provides:
- the observed building characteristics
- baseline emissions for the analysis
- a way to derive ACPs and identify noncompliant buildings

*ComStock* provides simulated commercial building characteristics, baseline energy consumption, and estimates of the impacts of energy-efficiency upgrades @comstock. Our data flow uses the Suffolk County basic annual results and full metadata tables, covering the baseline and the upgrades in @tab:upgrades. Energy measurements are standardized, and weighted energy consumption values are converted to per-building quantities using ComStock simulation weights.

*BTB* provides technology-level performance and installation cost estimates for building efficiency measures @btb. Its commercial dataset contains cost parameters for technologies such as lighting, building envelope improvements, and HVAC equipment. We use these data to estimate the installation costs of the components of the thirteen retrofit options in @tab:upgrades, and of the like-for-like equipment that options without heating and cooling upgrades must eventually replace.

== Data Integration and Optimization

*Building matching.* BERDO and ComStock cannot be joined directly by building identifier because BERDO represents real buildings, while ComStock contains synthetic building simulations. We use k-nearest-neighbor (KNN) matching with a custom distance function to identify representative ComStock models for each BERDO office building @berdo @comstock.

First, a property-type crosswalk restricts candidate ComStock models to building types compatible with each BERDO property type. Then similarity is calculated using gross floor area, site energy use intensity (EUI), fuel-consumption shares, and number of stories.

The distance function combines the absolute logarithmic differences in building size, EUI, and stories with half the sum of absolute differences in fuel shares:

$
  d(b,c) & = abs(ln(A_b / A_c)) \
         & + abs(ln("EUI"_b / "EUI"_c)) \
         & + 0.5 sum_f abs(s_(b,f) - s_(c,f)) \
         & + abs(ln(S_b / S_c))
$

where $A$ denotes gross floor area, $"EUI"$ represents site energy use intensity, and $s$ represents the share of energy consumption attributed to each fuel category. The fuel categories include electricity, natural gas, district energy, and oil/propane. $S$ is the number of stories, which sets how much of a building's envelope is roof rather than wall.

Neither BERDO nor the city's assessor reports stories for commercial buildings, so we estimate them from the city's building roof outlines, which carry 2010 LiDAR roof heights @boston-buildings, joined to the 2025 parcels @boston-parcels. A building's stories are its floor area divided by its parcel's footprint when that agrees within a factor of 1.6 with roof height divided by a 13 ft floor-to-floor height, and the height estimate otherwise. The two estimates agree for 218 of the 252 offices with both. Of the 297 offices, 267 receive an estimate; for the other 30 the stories term is zero for every candidate.

For each BERDO building, eligible ComStock simulations are ranked by increasing distance. The closest $k$ simulations are retained, where $k$ is a configurable matching parameter. These models provide representative building characteristics and retrofit performance estimates.

Two refinements were adopted after leave-one-out validation (@tab:matching-validation). Buildings that use district energy are matched only to simulations that also use it, and the others only to simulations without it; otherwise a district-heated building's district emissions receive no upgrade ratio. With $k = 20$, each simulation is weighted by its inverse distance, $w_(b c) = 1 \/ (d(b,c) + 10^(-6))$.

*Retrofit performance estimation.* ComStock baseline and upgrade scenarios are linked using their synthetic building identifiers. For each BERDO building and upgrade, the ratio of total upgraded to baseline energy consumption, weighted by $w_(b c)$, is calculated separately for electricity, natural gas, oil/propane, district heating, and district cooling across the matched simulations. The thirteen upgrades considered are listed in @tab:upgrades.

#figure(
  table(
    columns: (auto, auto, 1fr),
    align: (right, left, left),
    stroke: none,
    inset: (x: 4pt, y: 3pt),
    table.hline(),
    table.header([*ID*], [*Upgrade*], [*Measures*]),
    table.hline(stroke: 0.5pt),
    table.cell(colspan: 3, emph[Individual measures]),
    [43], [LED lighting], [LED lighting],
    [48], [Wall insulation], [Exterior wall insulation],
    [49], [Roof insulation], [Roof insulation],
    [52], [New windows], [High-performance windows],
    [12], [VRF], [Variable refrigerant flow with dedicated outdoor air],
    [29], [Geothermal], [Packaged water-to-air ground-source heat pump],
    [46], [Rooftop PV], [Photovoltaics on 40% of the roof],
    table.hline(stroke: 0.5pt),
    table.cell(colspan: 3, emph[Packages]),
    [54], [Package 1], [Wall and roof insulation; new windows],
    [55], [Package 2], [LED lighting; variable-speed heat pump RTU or heat pump boiler],
    [56], [Package 3], [Packages 1 and 2 combined],
    [57], [Package 4], [Package 2 with a standard-performance heat pump RTU],
    [58], [Package 5], [Heat pump RTU or boiler; economizer; demand-controlled ventilation; energy recovery],
    [65], [Package 12], [Rooftop PV and roof insulation],
    table.hline(),
  ),
  caption: [ComStock upgrades considered. IDs are ComStock 2025 upgrade numbers. RTU here stands for roof top unit.],
  placement: auto,
) <tab:upgrades>

The fuel-specific ratios are applied to the corresponding BERDO building's observed energy consumption and greenhouse gas emissions. This approach preserves the building's reported emissions baseline and fuel-specific emissions factors while transferring the modeled effects of ComStock upgrades.

If the matched simulations have no baseline consumption for a particular fuel, its ratio is set to one, leaving that fuel unchanged. Upgrade applicability is also summarized across the matched simulations. Because BERDO does not contain a complete inventory of installed equipment, the estimated impacts represent modeled retrofit opportunities rather than verified building-specific improvements.

*Installation cost estimation.* Selected ComStock upgrades and packages are mapped to corresponding BTB technologies @btb. Installation costs are estimated from applicable component quantities and BTB unit prices, with building-level scaling where appropriate. Low, mid, and high cost estimates are retained. Options that keep the existing heating and cooling equipment are also charged for replacing it like-for-like with gas rooftop units and boilers, sized from the matched simulations; heat pump, VRF, and geothermal options replace it instead. Basic completeness and unit-consistency checks passed, while component sizing and technology-price assumptions require further validation.

The integration workflow is summarized in @fig:pipeline.


// Methodology figure

#let flow_node(pos, heading, detail, name) = node(
  pos,
  align(center)[
    // The IEEE template justifies and hyphenates body text; keep boxes ragged.
    #set par(justify: false)
    #set text(hyphenate: false)
    #text(size: 7.5pt, weight: "bold")[#heading] \
    #text(size: 7pt)[#detail]
  ],
  name: name,
  width: 1.32in,
  inset: 4pt,
  stroke: 0.6pt + black,
  corner-radius: 0pt,
)

#figure(
  diagram(
    spacing: (10pt, 6pt),
    edge-stroke: 0.6pt,
    mark-scale: 70%,

    // Input datasets
    flow_node(
      (0, 0),
      "BERDO",
      [Observed office buildings: area, EUI, fuel use, GHG],
      <berdo>,
    ),
    flow_node(
      (0, 1),
      "Boston buildings and parcels",
      [
        Roof outlines, LiDAR heights, and parcels from
        data.boston.gov @boston-buildings @boston-parcels;
        estimated stories
      ],
      <stories>,
    ),
    flow_node(
      (0, 2),
      "ComStock",
      [Synthetic baselines and upgrade simulations],
      <comstock>,
    ),
    flow_node(
      (0, 3),
      "NLR BTB",
      [Technology-level installation cost parameters],
      <btb>,
    ),

    // Data processing
    flow_node(
      (1, 1),
      [BERDO--ComStock matching],
      [
        Property-type crosswalk;
        rank by custom distance $d(b,c)$
        over area, EUI, fuel shares, and stories;
        retain $k$ nearest simulations
      ],
      <match>,
    ),
    flow_node(
      (1, 3),
      "Technology cost mapping",
      [
        Map package components
        to BTB cost functions
      ],
      <map>,
    ),

    // Intermediate outputs
    flow_node(
      (2, 1),
      "Retrofit emissions estimation",
      [
        Pooled fuel-specific upgrade ratios;
        projected emissions for each
        BERDO building and package
      ],
      <emis>,
    ),
    flow_node(
      (2, 3),
      "Installation cost estimation",
      [
        Estimated capital cost
        per building and package
      ],
      <cost>,
    ),

    // Energy and emissions scenarios
    flow_node(
      (3.5, 0),
      "EIA AEO2026",
      [New England commercial energy price scenarios],
      <aeo>,
    ),
    flow_node(
      (2.5, 0),
      "NLR Cambium 2024",
      [ISO-NE grid emission rates for climate damages],
      <cambium>,
    ),

    // Optimization
    flow_node(
      (3, 2),
      "BERDO 2030 cost comparison",
      [
        Thirteen retrofit options and no-retrofit
        alternative; capital, energy bills, and
        residual Alternative Compliance Payments
      ],
      <cmp>,
    ),
    flow_node(
      (4, 2),
      "Optimal building-level decision",
      [
        Minimum-cost option:
        a retrofit option or ACP-only
      ],
      <dec>,
    ),

    edge(<berdo>, <match>, "-|>"),
    edge(<stories>, <match>, "-|>"),
    edge(<comstock>, <match>, "-|>"),
    edge(<btb>, <map>, "-|>"),
    edge(<match>, <emis>, "-|>"),
    edge(<map>, <cost>, "-|>"),
    edge(<emis>, <cmp>, "-|>"),
    edge(<cost>, <cmp>, "-|>"),
    edge(<aeo>, <cmp>, "-|>"),
    edge(<cambium>, <cmp>, "-|>"),
    edge(<cmp>, <dec>, "-|>"),
  ),

  placement: top,
  scope: "parent",

  caption: [
    Data integration and optimization framework
    for Boston office buildings. BERDO observations, with story counts estimated from data.boston.gov building and parcel data @boston-buildings @boston-parcels, are linked to ComStock simulations through property-type-constrained nearest-neighbor matching. Estimated retrofit performance,
    BTB installation costs, AEO energy price scenarios @aeo, and Cambium grid emission rates @cambium support the selection of cost-effective 2030 compliance options.
  ],
) <fig:pipeline>


*2030 compliance assessment.* BERDO establishes an office building emissions standard of 3.2 kg $"CO"_2"e"$ per square foot per year for the 2030-2034 compliance period @berdo-standards. For each building and retrofit scenario, estimated emissions are divided by gross floor area and compared with the applicable standard. The electricity portion of each building's emissions follows BERDO's projected electricity emissions factor year by year, which falls 15% from 2030 to 2034 @berdo.

The existing data flow's compliance model calculates projected emissions intensity, whether the building meets the standard, and the amount of emissions exceeding the limit. It also includes an no-upgrade scenario representing no retrofit.

For emissions exceeding the limit, BERDO permits ACPs. The current payment rate is \$234 per metric ton of CO#sub[2]e above the emissions limit @berdo-acp. Annual ACP obligations are estimated from the remaining excess emissions in each year after each retrofit scenario.


*Cost optimization.* The proposed framework identifies the most cost-effective retrofit decision for meeting Boston office buildings' 2030 BERDO obligations. Candidate retrofit updates/packages are compared with a no-retrofit alternative using a five-year financial evaluation period (2030--2034).

For each alternative, total modeled cost consists of capital, energy bills, and cumulative Alternative Compliance Payments (ACPs) associated with any remaining excess emissions. Because equipment lasts a median of 21 years, the five-year view charges five years of its equivalent annual cost at a 7% real discount rate, the return on private capital in OMB's regulatory guidance @omb-a4, reinstated in 2025 @omb-m2515, rather than its full price, and the like-for-like replacement of kept equipment is charged the same way. The baseline analysis assumes constant energy use, energy prices, and ACP rates throughout the evaluation period. The model identifies the lowest five-year-cost alternative for each building. The cheapest retrofit predicted to meet the 2030 emissions standard is also evaluated separately.

*Uncertainty.* A 20-year life-cycle cost, following the global cost method of EN 15459-1 @en15459 and the EU cost-optimal framework @eu-cost-optimal, discounts capital replacements, energy bills under EIA price scenarios @aeo, and either ACPs or climate damages. The owner's view discounts at the same 7% and pays ACPs. Society's view discounts at 2%, the rate underlying the EPA's social cost of carbon, and prices all emissions at about \$230 per metric ton of CO#sub[2]e in 2020 dollars @epa-scghg, with electricity following NLR Cambium's projected ISO-NE grid emission rates @cambium. A Monte Carlo analysis of the 20-year horizon samples installation costs, energy prices, and the leave-one-out retrofit-performance errors to estimate how often each recommendation stays the cheapest and compliant.



== Evaluation

We evaluated installation costs, projected greenhouse gas emissions reductions, and 2030 BERDO compliance outcomes across the tested upgrades and packages. The no-retrofit alternative served as the financial baseline for comparing modeled installation and ACP costs.

We examined the lowest-cost overall decision and the lowest-cost compliant retrofit separately, distinguishing financial preference for ACPs from predicted emissions compliance.

BERDO--ComStock matching quality was evaluated using matching distances and differences in building characteristics. Matching configurations (the number of neighbors $k$, inverse-distance weighting, and the district-energy rule) were compared by leave-one-out validation on 618 ComStock office simulations: each simulation's upgrade emissions were predicted from its neighbors and compared with ComStock's result. Sensitivity analysis then varied k from 1 to 20 and compared recommendations and cheapest compliant retrofits against k=20, rebuilding costs, emissions, and ACPs for each k.

The analysis has several limitations. ComStock represents simulated rather than observed building systems, while BERDO does not provide a complete inventory of existing equipment. Additionally, the emissions projections hold energy use and non-electric emissions factors constant, and electricity follows BERDO's projected factor rather than an observed grid. Installation costs are estimated from technology-level benchmarks rather than building-specific engineering assessments.

The resulting recommendations will therefore be interpreted as preliminary investment estimates for the 2030--2034 period rather than verified retrofit plans.


= Preliminary Results

== Data Exploration and Feasibility

Preliminary exploration focused on assessing the availability and suitability of the BERDO, ComStock, and BTB datasets for the proposed analysis.

The BERDO disclosure provides building-level information on property type, gross floor area, energy consumption, greenhouse gas emissions, and more @berdo. The dataset published for 2026 contains 5,591 building records, a substantial amount for analysis. However, because BERDO relies on self-reported building information, missing and inconsistent values limit the number of usable records. An examination of data completeness across building categories revealed considerable variation, with office buildings exhibiting higher completeness than other building types (@fig:berdo-heatmap).

Of the 5,591 records, 431 buildings with a BERDO ID were identified as having office space as their primary or sole use. Of these, 186 (43.2%) also contained non-office, non-parking uses, highlighting the frequency of mixed-use properties (@fig:berdo-types). This subset provides a substantial population for the proposed BERDO–ComStock matching procedure, although differences in building composition may introduce additional uncertainty.

To measure the potential need for decarbonization investments, reported greenhouse gas (GHG) emissions intensities were compared against the 2030-2034 BERDO standard for offices of 3.2 kg of $"CO"_2"e"$ per square foot per year @berdo-standards. 290 of the 410 office buildings reported GHG intensity values, of which 96 or 33.1% exceeded the 2030 standard (@fig:berdo-GHGvsStandard). This number suggests that a substantial portion of offices might face compliance challenges, highlighting the need for the evaluation of retrofit upgrades and their cost.

ComStock provides baseline simulations and retrofit scenarios with information on building characteristics, fuel consumption, and upgrade applicability @comstock. These variables support the proposed building-matching procedure and estimation of retrofit performance.

Exploration of the BTB commercial dataset identified installation cost information for technologies corresponding to components of the candidate ComStock retrofit packages @btb. Basic package-cost completeness and unit-consistency checks passed. Physical quantities and technology-price assumptions still require validation.


== Integration and Financial Sensitivity

In the integrated analysis, all 297 office buildings were matched to ComStock simulations. Of these, 99 exceed the 2030 emissions standard at today's electricity emissions factor and 81 at BERDO's projected 2030 factor. At k=20, 71 of those 81 buildings had at least one predicted compliant retrofit among thirteen tested options. The five-year model recommends a retrofit for all 81 and a compliant one for 36, most often rooftop PV with roof insulation (40 buildings); heat pump options are chosen for 19. Over 20 years under projected grid emissions and prices, the cheapest option meets the standard for 36 buildings from the owner's perspective and 41 from society's.

In leave-one-out validation, adding stories to the distance lowered the mean absolute error at k=20 from 7.05 to 6.58 percentage points of emissions reduction, and the median from 3.80 to 3.00, though the 90th percentile rose from 18.08 to 18.83. Inverse-distance weighting with the district-energy rule remained the best configuration tested, within 0.01 points of its minimum at k=19. Compared with unweighted matching without the rule at the same k, it was 0.10 points better (95% CI 0.01--0.19), and 0.21 points better for district-energy simulations, a borderline difference (95% CI 0.003--0.41). Held-out simulations have their exact story counts, while BERDO buildings have estimates, so the stories term likely helps less in practice.

Compared with k=20, the cheapest compliant retrofit changed for 42 of 69 commonly eligible buildings at k=1, 14 of 70 at k=10, and 5 of 71 at k=19.

Two buildings illustrate this sensitivity. For building 104777 (160-170 State Street, Boston), Package 2 was the cheapest compliant retrofit at most k, but Package 5 at k=1 and 4. For building 105302 (2-16 Tremont Street, Boston), roof insulation was the cheapest compliant option at k=1-2, Package 4 at k=3, and Package 2 from k=4 on.

These findings demonstrate sensitivity of investment recommendations to neighbor selection, particularly near compliance thresholds.


== Current Limitations

The preliminary BERDO analysis revealed some data quality limitations. Of the 410 buildings containing office space, 120 (29.3%) lack reported GHG emissions intensity data, limiting the coverage of the 2030 compliance assessment.

Additionally, the selected buildings set contains both single-use office buildings and mixed-use buildings where offices account for the largest part. For mixed-use spaces, reported energy consumption and emissions data may reflect the use of spaces other than offices, which introduces some uncertainty in matching these buildings to ComStock simulations. Verifying the distribution of energy consumption on each building would require property-level information, potentially from individual building owners or management companies, which is beyond the scope of this project.

The integration and matching sensitivity models have been evaluated for internal consistency and robustness to k. However, observed post-retrofit outcomes are unavailable, so predictive accuracy remains unverified. Installation costs and building-level five-year cost comparisons have been calculated, but cost assumptions require further validation: the existing equipment's type and age are inferred rather than observed, and incentives such as Mass Save rebates are not included. Multi-year optimization currently remains outside the implemented scope.

// ---- 9: discussion --------------------------------------------------------

= Discussion

Preliminary exploration of the BERDO dataset highlighted the importance of data completeness in providing reliable building decarbonization recommendations. Although office buildings exhibited relatively high data completeness, records with missing data and the presence of mixed-use properties can introduce potential uncertainty to the analysis. These findings suggest that further investigation of data quality and matching reliability can improve the results.

We evaluated BERDO--ComStock matching using building-characteristic differences and sensitivity to the number of nearest neighbors. Retrofit recommendations changed for some buildings when k varied, particularly where predicted emissions were close to the compliance threshold. Comparing neighbor aggregation methods led us to weight neighbors by inverse distance and to match district-energy buildings only to district-energy simulations, and adding stories estimated from city building footprints and roof heights reduced the leave-one-out error further.

A second direction involves examining methods of addressing the missing information of the BERDO dataset. Further analysis could reveal if missing measurements, such as GHG intensity, can be calculated from related data. Where calculations are not possible, the option of using statistical imputation or predictive modeling could be explored. However, the suitability of these methods would rely on the availability of reliable predictors and the potential uncertainty of estimated data.

All things considered, both directions aim to improve the reliability of the resulting decarbonization recommendations. Sensitivity analysis could help determine how differences in matching parameters and assumptions about missing data affect the resulting suggestions.

Our approach now includes energy bills alongside installation costs, over 5 and 20 years, with the 20-year view following the EIA's _Annual Energy Outlook_ @aeo price scenarios. Charging long-lived equipment its full price against five years of savings, and leaving kept equipment free, had penalized electrification; annualizing capital and charging like-for-like replacement raised the compliant five-year recommendations from 3 to 33 of 81 (36 after stories were added to the matching). BERDO's flat ACP per ton remains the main barrier to deeper retrofits, since it gives no extra reward for meeting the standard.

Our second missing piece is MACC for a baseline comparison. Our evaluation uses individual upgrades and packages of upgrades. These potential paths will be evaluated as the project progresses, alongside the completion of dataset integration, matching, and optimization.

// ---- 10: statement of contributions ---------------------------------------

= Statement of Contributions

- *Konstantinos Theodoropoulos:*

  - Reaching out to potential sponsors
  - BERDO exploration and validation
  - Attending office hours with Dr. Bemis

- *Zachary Wegrzyniak:*

  - data pipeline in dbt and DuckDB
    - ComStock and BERDO join
    - Mixed-use evaluation
  - editing
  - repo setup

- *Kateryna Lysytsyna:*
  - ComStock exploration and retrofit selection
  - BTB-ComStock cost integration and validation
  - BERDO-ComStock join evaluation
  - Emissions, compliance, and financial sensitivity analysis
  - Visualizations



= AI Use Disclosure

Claude Opus 5.5 and ChatGPT 6.1 were used for:
- data retrieval
- portions of the data pipeline
- typesetting
- visualizations
- editing

// ---- 11: references -------------------------------------------------------

#bibliography("refs.yml")

// ---- 12: appendix ---------------------------------------------------------

#show figure.caption: set align(center)
// Appendix graphics float across both columns so they stay legible; body text
// and tables remain two-column.
#show figure.where(kind: image): set figure(placement: auto, scope: "parent")

= Appendix

This appendix provides the BERDO data diagnostics cited in the main report, the matching validation, and the cost model's equations. The source code and reproducibility scripts are available at
#link("https://github.com/wegry/DS5500")[github.com/wegry/DS5500].

== BERDO Data Exploration

These exploratory summaries precede the filtering and matching of the integrated analysis, so their populations differ from it and are reported separately.

#figure(
  image(
    "figures/berdo-emissions-standards.png",
    width: 55%,
  ),
  caption: [
    BERDO emissions-intensity standards by building use
    and five-year compliance period, expressed in
    kg CO#sub[2]e/ft#super[2]/year @berdo-standards.
  ],
  placement: auto,
) <fig:berdo-limits>

#figure(
  image(
    "figures/berdo-completeness.png",
    width: 82%,
  ),
  caption: [
    Completeness of selected BERDO attributes across building-use categories. Each cell represents the percentage of records with nonmissing observations for the corresponding
    variable.
  ],
) <fig:berdo-heatmap>

#figure(
  image(
    "figures/berdo-property-types.png",
    width: 80%,
  ),
  caption: [
    Composition of office-related BERDO properties according to the reported proportion of non-office, non-parking floor area.
  ],
) <fig:berdo-types>

#figure(
  image(
    "figures/berdo-intensity-vs-benchmark.png",
    width: 80%,
  ),
  caption: [
    Distribution of reported office-building greenhouse gas emissions intensity compared with the 2030 BERDO office standard.
  ],
) <fig:berdo-GHGvsStandard>

Office buildings showed relatively high completeness of floor-area and energy-consumption variables, making them suitable candidates for integration with ComStock. However, missing emissions observations reduce the number of records available for compliance assessment, and missingness may introduce selection bias if buildings with incomplete reporting differ systematically from those retained. Mixed-use composition matters because BERDO reports energy consumption and emissions at the building level, so a building's energy profile may include activities other than those of a typical office.

== Matching Validation

Each of 618 ComStock office simulations in turn plays a BERDO building: it is hidden, its upgrade emissions are predicted from its $k$ nearest other simulations, and the prediction is compared with ComStock's simulated result across the thirteen upgrades. This measures how well retrofit effects transfer between simulated buildings, not real-world accuracy.

// two decimals, keeping trailing zeros
#let two(x) = {
  let cents = int(calc.round(float(x) * 100))
  let r = calc.rem(cents, 100)
  str(calc.quo(cents, 100)) + "." + (if r < 10 { "0" } else { "" }) + str(r)
}
#let validation = csv("data/matching_validation.csv", row-type: dictionary).filter(
  r => r.k in ("10", "20"),
)

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (right, left, left, right, right),
    stroke: none,
    inset: (x: 4pt, y: 3pt),
    table.hline(),
    table.header([*$k$*], [*Weighting*], [*District rule*], [*MAE*], [*MAE, district*]),
    table.hline(stroke: 0.5pt),
    ..validation
      .map(r => (
        r.k,
        if r.method == "inverse_distance" [Inverse distance] else [Equal],
        if r.rule == "true" [Yes] else [No],
        two(r.mae_pp),
        two(r.mae_pp_district_models),
      ))
      .flatten(),
    table.hline(),
  ),
  caption: [
    Leave-one-out mean absolute error of predicted emissions reductions, in percentage points, for all 618 simulations and the 73 that use district energy. The project uses $k = 20$ with inverse-distance weighting and the district rule.
  ],
  placement: none,
) <tab:matching-validation>

== Retrofit Emissions Estimation

For building $b$, upgrade $p$, fuel $f$, and matched simulations $N_b$, with weights $w_(b c)$:

$
  r_(b,p,f) = (sum_(c in N_b) w_(b c) U_(c,p,f)) / (sum_(c in N_b) w_(b c) B_(c,f))
$

where $U$ and $B$ are the simulations' upgraded and baseline use of fuel $f$. The projected emissions in year $y$ apply these ratios to the building's reported emissions $G_(b,f)$, with the electricity part scaled by BERDO's electricity factor index $e_y$ (2025 = 1):

$
  G_(b,p,y) = G_(b,"elec") r_(b,p,"elec") e_y + sum_(f != "elec") G_(b,f) r_(b,p,f)
$

If the matched simulations have no baseline consumption for a fuel, its ratio is one.

== Five-Year Cost Calculation

Each component $m$ of an upgrade, with installed cost $K_m$ and BTB lifetime $L_m$, is charged five years of its equivalent annual cost at the owner's discount rate $rho = 0.07$:

$
  a(L) = rho / (1 - (1 + rho)^(-L))
$

$
  C_(b,p) = & sum_(m in p) K_m min(1, 5 a(L_m)) + bb(1)_p sum_(e in H_b) K_e min(1, 5 a(L_e)) \
            & + sum_(y=2030)^(2034) 0.234 max(0, G_(b,p,y) - 3.2 A_b) + 5 times E_(b,p)
$

where $H_b$ is the building's existing heating and cooling equipment and $bb(1)_p$ is one for options that keep it, $0.234$ is the ACP in dollars per kilogram, $A_b$ is floor area, and $E_(b,p)$ is the annual energy bill at constant prices. Running costs are not discounted over the five years.
