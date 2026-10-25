
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
  abstract: [Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) requires large buildings to meet increasingly strict greenhouse gas emissions limits, with a major compliance milestone in 2030. This project aims to identify cost-effective decarbonization options for Boston office buildings by considering BERDO disclosures, ComStock building simulations, and Buildings Technology Baseline (BTB) installation cost data. The integrated analysis includes 297 matched office buildings, 99 of which exceed 2030 emmissions standard. A data intergration pipeline was developed to match BERDO buildings with representative ComStock simulations and estimate potential retrofit emissions reductions. Ongoing work focuses on integrating installation costs and optimizing the selection of one of four retrofit packages or Alternative Compliance Payments (ACP) over the 2030-2034 period. The resulting framework aims to support investment decisions for office buildings by balancing emissions reductions, compliance requirements, and budget constraints.
  ],
  index-terms: (
    "Building decarbonization",
    "BERDO",
    "Retrofit optimization",
    "Office buildings",
    "Emissions comliance",
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

*BTB* provides technology-level performance and installation cost estimates for building efficiency measures @btb. Its commercial dataset contains cost parameters for technologies such as lighting, building envelope improvements, and HVAC equipment. We use these data to estimate the installation costs of components included in four currently selected retrofit packages.

== Data Integration and Optimization

*Building matching.* BERDO and ComStock cannot be joined directly by building identifier because BERDO represents real buildings, while ComStock contains synthetic building simulations. We use k-nearest-neighbor (KNN) matching with a custom distance function to identify representative ComStock models for each BERDO office building @berdo @comstock.

First, a property-type crosswalk restricts candidate ComStock models to building types compatible with each BERDO property type. Then similarity is calculated using gross floor area, site energy use intensity (EUI), and fuel-consumption shares.

The distance function combines the absolute logarithmic differences in building size and EUI with half the sum of absolute differences in fuel shares:

$
  d(b,c) & = abs(ln(A_b / A_c)) \
         & + abs(ln("EUI"_b / "EUI"_c)) \
         & + 0.5 sum_f abs(s_(b,f) - s_(c,f))
$

where $A$ denotes gross floor area, $"EUI"$ represents site energy use intensity, and $s$ represents the share of energy consumption attributed to each fuel category. The fuel categories include electricity, natural gas, district energy, and oil/propane.

For each BERDO building, eligible ComStock simulations are ranked by increasing distance. The closest $k$ simulations are retained, where $k$ is a configurable matching parameter. These models provide representative building characteristics and retrofit performance estimates.

*Retrofit performance estimation.* ComStock baseline and upgrade scenarios are linked using their synthetic building identifiers. For each BERDO building and upgrade, the ratio of total upgraded to baseline energy consumption is calculated separately for electricity, natural gas, oil/propane, district heating, and district cooling across the matched simulations. The four individual measures and four packages considered are listed in @tab:upgrades.

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
    table.hline(stroke: 0.5pt),
    table.cell(colspan: 3, emph[Packages]),
    [54], [Package 1], [Wall and roof insulation; new windows],
    [55], [Package 2], [LED lighting; variable-speed heat pump RTU or heat pump boiler],
    [56], [Package 3], [Packages 1 and 2 combined],
    [57], [Package 4], [Package 2 with a standard-performance heat pump RTU],
    table.hline(),
  ),
  caption: [ComStock upgrades considered. IDs are ComStock 2025 upgrade numbers. RTU here stands for roof top unit.],
  placement: auto,
) <tab:upgrades>

The fuel-specific ratios are applied to the corresponding BERDO building's observed energy consumption and greenhouse gas emissions. This approach preserves the building's reported emissions baseline and fuel-specific emissions factors while transferring the modeled effects of ComStock upgrades.

If the matched simulations have no baseline consumption for a particular fuel, its ratio is set to one, leaving that fuel unchanged. Upgrade applicability is also summarized across the matched simulations. Because BERDO does not contain a complete inventory of installed equipment, the estimated impacts represent modeled retrofit opportunities rather than verified building-specific improvements.

*Installation cost estimation.* Selected ComStock upgrades and packages are mapped to corresponding BTB technologies @btb. Installation costs are estimated from applicable component quantities and BTB unit prices, with building-level scaling where appropriate. Low, mid, and high cost estimates are retained. Basic completeness and unit-consistency checks passed, while component sizing and technology-price assumptions require further validation.

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
      "ComStock",
      [Synthetic baselines and upgrade simulations],
      <comstock>,
    ),
    flow_node(
      (0, 2),
      "NLR BTB",
      [Technology-level installation cost parameters],
      <btb>,
    ),

    // Data processing
    flow_node(
      (1, 0.5),
      [BERDO--ComStock matching],
      [
        Property-type crosswalk;
        rank by custom distance $d(b,c)$;
        retain $k$ nearest simulations
      ],
      <match>,
    ),
    flow_node(
      (1, 2),
      "Technology cost mapping",
      [
        Map package components
        to BTB cost functions
      ],
      <map>,
    ),

    // Intermediate outputs
    flow_node(
      (2, 0.5),
      "Retrofit emissions estimation",
      [
        Pooled fuel-specific upgrade ratios;
        projected emissions for each
        BERDO building and package
      ],
      <emis>,
    ),
    flow_node(
      (2, 2),
      "Installation cost estimation",
      [
        Estimated capital cost
        per building and package
      ],
      <cost>,
    ),

    // Optimization
    flow_node(
      (3, 1.25),
      "BERDO 2030 cost comparison",
      [
        Four retrofit packages and no-retrofit
        alternative; installation costs plus
        residual Alternative Compliance Payments
      ],
      <cmp>,
    ),
    flow_node(
      (4, 1.25),
      "Optimal building-level decision",
      [
        Minimum-cost option:
        retrofit package 1--4 or ACP-only
      ],
      <dec>,
    ),

    edge(<berdo>, <match>, "-|>"),
    edge(<comstock>, <match>, "-|>"),
    edge(<btb>, <map>, "-|>"),
    edge(<match>, <emis>, "-|>"),
    edge(<map>, <cost>, "-|>"),
    edge(<emis>, <cmp>, "-|>"),
    edge(<cost>, <cmp>, "-|>"),
    edge(<cmp>, <dec>, "-|>"),
  ),

  placement: top,
  scope: "parent",

  caption: [
    Data integration and optimization framework
    for Boston office buildings. BERDO observations are linked to ComStock simulations through property-type-constrained nearest-neighbor matching. Estimated retrofit performance and
    BTB installation costs support the selection of cost-effective 2030 compliance options.
  ],
) <fig:pipeline>


*2030 compliance assessment.* BERDO establishes an office building emissions standard of 3.2 kg $"CO"_2"e"$ per square foot per year for the 2030-2034 compliance period @berdo-standards. For each building and retrofit scenario, estimated emissions are divided by gross floor area and compared with the applicable standard.

The existing data flow's compliance model calculates projected emissions intensity, whether the building meets the standard, and the amount of emissions exceeding the limit. It also includes an no-upgrade scenario representing no retrofit.

For emissions exceeding the limit, BERDO permits ACPs. The current payment rate is \$234 per metric ton of CO#sub[2]e above the emissions limit @berdo-acp. Annual ACP obligations are estimated from the remaining excess emissions after each retrofit scenario.


*Cost optimization.* The proposed framework identifies the most cost-effective retrofit decision for meeting Boston office buildings' 2030 BERDO obligations. Candidate retrofit updates/packages are compared with a no-retrofit alternative using a five-year financial evaluation period (2030--2034).

For each alternative, total modeled cost consists of the estimated installation cost and cumulative Alternative Compliance Payments (ACPs) associated with any remaining excess emissions. The baseline analysis assumes constant annual emissions and ACP rates throughout the evaluation period. The model identifies the lowest five-year-cost alternative for each building. The cheapest retrofit predicted to meet the 2030 emissions standard is also evaluated separately.



== Evaluation

We evaluated installation costs, projected greenhouse gas emissions reductions, and 2030 BERDO compliance outcomes across the tested upgrades and packages. The no-retrofit alternative served as the financial baseline for comparing modeled installation and ACP costs.

We examined the lowest-cost overall decision and the lowest-cost compliant retrofit separately, distinguishing financial preference for ACPs from predicted emissions compliance.

BERDO--ComStock matching quality was evaluated using matching distances and differences in building characteristics. Sensitivity analysis varied k from 1 to 10 and compared projected emissions, compliance classifications, and cheapest compliant retrofits against k=10. Installation costs and retrofit applicability were held fixed across k.

The analysis has several limitations. ComStock represents simulated rather than observed building systems, while BERDO does not provide a complete inventory of existing equipment. Additionally, the current emissions projections hold reported fuel-specific emissions factors constant, without explicitly modeling future changes in electricity emissions intensity. Installation costs are estimated from technology-level benchmarks rather than building-specific engineering assessments.

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

In the integrated analysis, all 297 office buildings were matched to ComStock simulations, with 99 of them exceededing the modeled 2030 emissions standard. At k=10, 75 of those buildings had at least one predicted compliant retrofit among eight tested options.

Compared with k=10, the cheapest compliant retrofit changed for 23 of 68 commonly eligible buildings at k=1 and 4 of 74 at k=9. Installation costs and retrofit applicability were held fixed across k, while predicted emissions and ACPs were recalculated.

Two buildings illustrate this sensitivity. For building 104777 (160-170 State Street, Boston), Package 4 was the cheapest compliant retrofit for k=1-9, but Package 2 became preferable at k=10 after Package 4 slightly exceeded the emissions limit. For building 105302 (2-16 Tremont Street, Bosoton), wall insulation first became compliant at k=4 and remained the cheapest compliant option through k=10.

These findings demonstrate sensitivity of investment recommendations to neighbor selection, particularly near compliance thresholds.


== Current Limitations

The preliminary BERDO analysis revealed some data quality limitations. Of the 410 buildings containing office space, 120 (29.3%) lack reported GHG emissions intensity data, limiting the coverage of the 2030 compliance assessment.

Additionally, the selected buildings set contains both single-use office buildings and mixed-use buildings where offices account for the largest part. For mixed-use spaces, reported energy consumption and emissions data may reflect the use of spaces other than offices, which introduces some uncertainty in matching these buildings to ComStock simulations. Verifying the distribution of energy consumption on each building would require property-level information, potentially from individual building owners or management companies, which is beyond the scope of this project.

The integration and matching sensitivity models have been evaluated for internal consistency and robustness to k. However, observed post-retrofit outcomes are unavailable, so predictive accuracy remains unverified. Installation costs and building-level five-year cost comparisons have been calculated, but cost assumptions require further validation, and multi-year optimization currently remains outside the implemented scope.

// ---- 9: discussion --------------------------------------------------------

= Discussion

Preliminary exploration of the BERDO dataset highlighted the importance of data completeness in providing reliable building decarbonization recommendations. Although office buildings exhibited relatively high data completeness, records with missing data and the presence of mixed-use properties can introduce potential uncertainty to the analysis. These findings suggest that further investigation of data quality and matching reliability can improve the results.

We evaluated BERDO--ComStock matching using building-characteristic differences and sensitivity to the number of nearest neighbors. Retrofit recommendations changed for some buildings when k varied, particularly where predicted emissions were close to the compliance threshold. Comparing alternative neighbor aggregation methods remains a possible extension.

A second direction involves examining methods of addressing the missing information of the BERDO dataset. Further analysis could reveal if missing measurements, such as GHG intensity, can be calculated from related data. Where calculations are not possible, the option of using statistical imputation or predictive modeling could be explored. However, the suitability of these methods would rely on the availability of reliable predictors and the potential uncertainty of estimated data.

All things considered, both directions aim to improve the reliability of the resulting decarbonization recommendations. Sensitivity analysis could help determine how differences in matching parameters and assumptions about missing data affect the resulting suggestions.

Our current approach does not take operating costs into consideration, only installation costs. Without operating costs in the mix, electrification is currently penalized by the initial up front cost of new equipment. Including operating costs would presumably include a time frame we would be evaluating such as 5, 10, 15, or 20 years. We may have to pull in something like _Annual Energy Outlook_ from the EIA @aeo for modeling natural gas and electricity costs in different scenarios.

Our second missing piece is MACC for a baseline comparison. Our evaluation uses individual upgrades and packages of upgrades, but without operating costs, once again it is not an apples-to-apples comparison. These potential paths will be evaluated as the project progresses, alongside the completion of dataset integration, matching, and optimization.

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

#set page(columns: 1)
#show figure.caption: set align(center)

= Appendix

This appendix provides supplementary data diagnostics, matching evaluation, sensitivity analysis, and financial validation supporting the results presented in the main report. All figures were generated from the project datasets and analysis pipeline. The source code and reproducibility scripts are available at
#link("https://github.com/wegry/DS5500")[github.com/wegry/DS5500].

== BERDO Data Exploration

The initial analysis evaluated the completeness and composition of BERDO disclosure records to determine their suitability for building-level decarbonization modeling. These exploratory summaries precede the additional filtering and integration used in the final BERDO-ComStock analysis.

=== Emissions Standards

#figure(
  image(
    "figures/berdo-emissions-standards.png",
    width: 75%),
  caption: [
    BERDO emissions-intensity standards by building use
    and five-year compliance period, expressed in
    kg CO#sub[2]e/ft#super[2]/year @berdo-standards.
  ],
) <fig:berdo-limits>

BERDO establishes progressively stricter emissions limits by property category and compliance period. Office buildings are subject to a standard of 3.2 kg CO#sub[2]e/ft#super[2]/year during 2030--2034. This threshold serves as the compliance criterion throughout the integrated retrofit analysis. Projected post-retrofit emissions are normalized by each building's reported floor area and compared with the applicable standard. 
The figure represents regulatory requirements rather
than observed building performance.

=== Data Completeness

#figure(
  image(
    "figures/berdo-completeness.png",
    width: 82%),
  caption: [
    Completeness of selected BERDO attributes across building-use categories. Each cell represents the percentage of records with nonmissing observations for the corresponding
    variable.
  ],
) <fig:berdo-heatmap>

For each building category and variable, completeness was calculated as:

$
"Completeness" = N_"nonmissing" / N_"total" times 100
$

The evaluation considered building floor area, reported greenhouse gas emissions, emissions intensity, applicable compliance standards, site energy consumption, and energy-use intensity. Office buildings showed relatively high completeness of floor-area and energy-consumption variables, making them suitable candidates for integration with ComStock However, missing emissions observations reduce the number of records available for compliance assessment. Missingness may also introduce selection bias if buildings with incomplete reporting differ systematically from those retained in the analysis.

=== Office-Building Composition

#figure(
  image(
    "figures/berdo-property-types.png",
    width: 80%),
  caption: [
    Composition of office-related BERDO properties according to the reported proportion of non-office, non-parking floor area.
  ],
) <fig:berdo-types>

Office-related properties were categorized according to their reported building-use
composition. The analysis distinguished buildings containing only office and parking uses from properties with additional non-office space. Mixed-use composition is relevant here because BERDO reports energy consumption and emissions at the building level. Consequently, the measured energy profile may incorporate activities with energy requirements different from those of a typical office building. This introduces uncertainty when matching BERDO properties to representative ComStock office simulations.

=== Reported Emissions Distribution

#figure(
  image(
    "figures/berdo-intensity-vs-benchmark.png",
    width: 80%),
  caption: [
    Distribution of reported office-building greenhouse gas emissions intensity compared with the 2030 BERDO office standard.
  ],
) <fig:berdo-GHGvsStandard>

Reported emissions intensity was calculated as total annual greenhouse gas emissions divided by gross floor area:

$
I_b = G_b / A_b
$

where $G_b$ is a building's annual emissions in kg CO#sub[2]e and $A_b$ is its gross floor area in square feet.

The distribution was compared with the 2030 office emissions standard to identify buildings potentially requiring decarbonization measures or Alternative Compliance Payments. The histogram shows substantial variation in reported emissions intensity across offices. The exploratory population differs from the integrated modeling population because additional
data preparation, eligibility criteria, and matching requirements are applied downstream.
These populations are therefore reported separately rather than treated as interchangeable.


== BERDO--ComStock Matching Evaluation

Because BERDO describes actual properties while ComStock contains simulated commercial buildings, direct matching by building identifier is not possible. Candidate ComStock simulations were restricted using compatible building types and ranked according to similarity in floor area, energy-use intensity, and fuel-consumption shares.

The matching distance is defined as:
$
  d(b,c) &= abs(ln(A_b / A_c)) + abs(ln("EUI"_b / "EUI"_c)) + 0.5 sum_f abs(s_(b,f) - s_(c,f))
$ where $b$ identifies a BERDO building, $c$ identifies a ComStock simulation, $A$ denotes floor area, $"EUI"$ denotes energy-use intensity, and $s_f$ represents the proportion of energy consumption attributed to fuel $f$.

The closest $k$ simulations are selected for each
BERDO building.

=== Matching Quality

#figure(
  image(
    "figures/matching_quality.svg",
    width: 82%),
  caption: [
    Median and 90th-percentile matching distance across BERDO buildings as a function of the number of nearest ComStock neighbors.
  ],
) <fig:matching-quality>

For each BERDO building, the average distance to its first $k$ matched ComStock simulations
was calculated. The distribution of these building-level average distances was then summarized using the median and 90th percentile. The median describes typical matching similarity, while the 90th percentile characterizes buildings with comparatively less similar matches.

As additional neighbors are included, the average matching distance may increase because more distant simulations enter the selected set. This illustrates the trade-off between matching similarity and the number of simulations used to estimate retrofit performance.

Matching distance is a measure of similarity in selected observed characteristics. It does
not establish that the matched models have identical equipment or reproduce actual building retrofit outcomes.

=== Retrofit Emissions Estimation

Retrofit effects were transferred from matched ComStock simulations to BERDO buildings through fuel-specific upgrade-to-baseline energy ratios.

For building $b$, package $p$, fuel $f$, and matched simulation set $N_b(k)$:

$
r_(b,p,f)(k) = (sum_(c in N_b(k)) U_(c,p,f)) / (sum_(c in N_b(k)) B_(c,f))
$
where $U$ is the upgraded fuel consumption and $B$ is the corresponding baseline fuel consumption.

The pooled ratio is calculated separately for each fuel category. This method weights individual retrofit ratios according to their baseline fuel consumption.

The projected annual emissions are:

$
G_(b,p,k) = sum_f G_(b,f) r_(b,p,f)(k)
$
where $G_(b,f)$ represents the corresponding reported BERDO baseline emissions.

If the matched simulations have no baseline consumption for a fuel, the model leaves
that fuel's emissions unchanged.

=== Emissions Sensitivity

#figure(
  image(
    "figures/emissions_sensitivity.svg",
    width: 82%),
  caption: [
    Mean and median absolute differences in predicted retrofit emissions reductions across nearest-neighbor configurations, relative to k=10. Differences are measured in percentage points.
  ],
) <fig:emissions-sensitivity>

To evaluate sensitivity to the matching parameter, emissions predictions were recalculated for different values of $k$. The configuration with $k = 10$ was used as the reference. For each building and retrofit scenario, the absolute difference in predicted emissions reduction was calculated as:

$
D_(b,p,k) = 100 abs(R_(b,p,k) - R_(b,p,10))
$
where $R$ denotes the fractional reduction relative to baseline emissions.

The mean and median absolute differences summarize the sensitivity of modeled retrofit effects to neighbor selection. A difference measured in percentage points should not be interpreted as a relative percentage difference. The analysis examines the stability of model-generated predictions under alternative neighbor configurations. It does not measure prediction accuracy, because observed post-retrofit outcomes are not available for comparison.

=== Compliance Classification Sensitivity

#figure(
  image(
    "figures/compliance_sensitivity.svg",
    width: 82%),
  caption: [
    Changes in predicted BERDO 2030 compliance classifications relative to k=10, showing both building-upgrade scenarios and distinct affected buildings.
  ],
) <fig:compliance-sensitivity>

For each building and retrofit scenario, the projected emissions intensity is:

$
I_(b,p,k) = G_(b,p,k) / A_b
$

A scenario is predicted to satisfy the 2030 standard when:

$
I_(b,p,k) <= 3.2
$

Compliance sensitivity was evaluated by comparing the resulting binary classifications across nearest-neighbor configurations. Two quantities were examined: the number
of building-upgrade scenarios with changed classifications and the number of distinct
BERDO buildings affected by those changes. These quantities differ because a single building may have several retrofit options whose classifications change. A relatively small change in projected emissions can cause a discrete change in compliance classification when the prediction lies close to the regulatory limit. Therefore, stable average emissions predictions do not necessarily imply stable compliance decisions.


== Compliance Availability and Financial Decisions

The integrated analysis evaluates individualretrofit measures and combined retrofit packages
using the 2030--2034 compliance standard. For each building, applicable retrofit options are evaluated according to their projected emissions and modeled financial cost. The financial analysis distinguishes the least-cost retrofit from the least-cost retrofit predicted to meet the emissions standard.

=== Availability of Compliant Retrofits

#figure(
  image(
    "figures/01_compliance_availability.svg",
    width: 82%),
  caption: [
    Availability of at least one predicted compliant retrofit among the evaluated measures and packages for buildings whose baseline emissions exceed the 2030 standard.
  ],
) <fig:compliance-availability>

For each office exceeding the baseline emissions threshold, compliance availability
was determined by examining all evaluated applicable retrofit options. A building was classified as having an available compliant retrofit if at least one candidate was predicted to reduce its emissions intensity to or below the 2030 standard.

The figure distinguishes buildings with at least one compliant modeled option from those for which none of the tested options achieved compliance.

Failure to identify a compliant option does not establish that compliance is technically impossible. It indicates only that the evaluated retrofit set was insufficient under the model assumptions.

=== Retrofit Recommendation Sensitivity

The lowest-cost compliant retrofit was identified for each building and matching configuration. The recommendation was determined by minimizing the modeled five-year cost among applicable options predicted to satisfy the emissions standard. Recommendations for k=1 through k=9 were compared with those obtained at k=10.

The following table is populated directly from the generated sensitivity analysis.

#let financial-rows = csv(
  "data/financial_k_summary.csv").slice(1)

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    align: center,
    inset: 6pt,

    table.header(
      [*$k$*],
      [*Changed recommendations / eligible buildings*],
      [*Reference choice loses compliance*],
    ),

    ..financial-rows.map(
      row => (
        text(row.at(0)),
        text(row.at(4) + " / " + row.at(2)),
        text(row.at(6)),
      )
    ).flatten()
  ),

  caption: [
    Sensitivity of lowest-cost compliant retrofit recommendations relative to k=10 Denominators include buildings with compliant candidates under both compared configurations.
  ],
) <tab:appendix-financial-sensitivity>

#figure(
  image(
    "figures/02_recommendation_sensitivity.svg",
    width: 82%),
  caption: [
    Number and proportion of buildings whose lowest-cost compliant retrofit differs from the reference k=10 recommendation.
  ],
) <fig:recommendation-sensitivity>

Recommendation changes were measured only for buildings with an available compliant option under both compared matching configurations. The number of buildings contributing to each comparison can therefore differ across values of $k$. A change in the recommended retrofit indicates sensitivity to neighbor selection but does not necessarily imply a substantial difference in cost. Furthermore, two matching configurations can produce the same recommendation even when their underlying emissions estimates differ. For this reason, recommendation stability was evaluated separately from emissions and compliance sensitivity.


== Financial Sensitivity Analysis

=== Five-Year Cost Calculation

The financial model evaluates each retrofit option over the 2030--2034 compliance period. Total modeled cost consists of theone-time installation cost and cumulative Alternative Compliance Payments associated with remaining excess emissions.

For building $b$, retrofit $p$, and matching configuration $k$:

$
  X_(b,p,k) = max(0, G_(b,p,k) - 3.2 A_b)
$

$
  C_(b,p,k) &= C_"installation"(b,p) + 5 times 0.234 times X_(b,p,k)
$

Here, $X_(b,p,k)$ represents annual emissions exceeding the 2030 building-specific allowance in kg CO#sub[2]e. The five-year cost combines the one-time installation expense with annual Alternative Compliance Payments at USD 0.234 per excess kilogram. The factor 0.234 represents the modeled ACP rate in USD per excess kilogram of CO#sub[2]e per year. Installation is treated as a one-time expense. Annual emissions and the payment rate are assumed constant
throughout the five-year period. Energy operating savings, maintenance, discounting, and future changes in emissions factors are excluded.

=== Median Financial Sensitivity

#figure(
  image(
    "figures/03_median_extra_cost.svg",
    width: 82%),
  caption: [
    Median additional five-year modeled cost of retaining the k=10 retrofit recommendation when a less expensive compliant option is available under an alternative k.
  ],
) <fig:median-extra-cost>

For each matching configuration, the analysis identified buildings whose lowest-cost compliant retrofit differed from the k=10 recommendation. When the original recommendation
remained compliant under the alternative configuration, the additional modeled cost of retaining it was calculated as:

$
Delta C_(b,k) = C_(b,p_(10),k) - C_(b,p_k,k)
$
where $p_(10)$ denotes the reference recommendation and $p_k$ denotes the least-cost compliant retrofit under the alternative configuration.

The median of these additional costs summarizes financial sensitivity among eligible changed decisions. Buildings for which the reference recommendation becomes noncompliant are excluded from this calculation. As a result, the median represents a conditional subset rather than the entire office-building population.

=== Maximum Financial Sensitivity

#figure(
  image(
    "figures/04_maximum_extra_cost.svg",
    width: 82%),
  caption: [
    Maximum additional five-year modeled cost across buildings with changed recommendations for which the k=10 choice remains compliant.
  ],
) <fig:maximum-extra-cost>

The maximum additional cost was calculated using the same eligibility criteria as the median analysis. Whereas the median summarizes typical additional cost within the selected subset, the maximum identifies the largest observed financial difference under each matching configuration. This provides information about potentially consequential individual decisions that may not be apparent from aggregate statistics. The reported maxima are descriptive model outputs, not confidence bounds or estimates of future realized losses.


== BTB Installation Cost Validation

Installation costs were estimated by mapping ComStock retrofit components to corresponding technologies in the Buildings Technology Baseline dataset. For component $m$, cost estimation depends on the applicable quantity and the corresponding BTB unit-cost function or rate.

At the package level:

$
C_"installation"(b,p) = sum_(m in p) C_(b,p,m)
$

Component costs are aggregated to produce low-, mid-, and high-range package installation estimates. The financial sensitivity analysis uses the mid-range cost estimate. Validation addresses several separate aspects of cost estimation: the availability of BTB mappings consistency of physical units, applicability of components to matched ComStock simulations, and reconciliation of component totals with package-level costs. The arithmetic reconciliation checks whether the sum of component estimates matches the corresponding modeled
package total. However, passing this check does not independently establish that component quantities accurately represent equipment installed in the actual BERDO building. Similarly, BTB benchmark costs are not equivalent to contractor quotes or building-specific engineering cost assessments.


== Building-Level Case Studies

Two BERDO office buildings were examined to illustrate how neighbor selection affects predicted compliance and lowest-cost retrofit recommendations.

=== Building 104777: State Street

For building 104777, the sensitivity analysis identifies a change in the preferred compliant
retrofit near the BERDO emissions-intensity threshold. Across neighboring configurations,
Package 4 and Package 2 exhibit different projected compliance outcomes while their estimated
installation costs remain fixed. The example illustrates how a relatively small difference in predicted emissions can change which retrofit is considered the lowest-cost compliant option.

=== Building 105302: Tremont Street

For building 105302, wall insulation becomes a compliant candidate when the estimated post-retrofit emissions intensity falls below the 2030 standard. The change in compliance status affects the set of eligible investment decisions and can change the minimum-cost compliant recommendation. This example demonstrates that financial decision sensitivity can arise from threshold crossings even when modeled installation costs are unchanged.

=== Compliance Cost Premiums

#figure(
  image(
    "figures/05_case_study_compliance_premiums.svg",
    width: 100%),
  placement: top,
  scope: "parent",
  caption: [
    Lowest-cost retrofit, lowest-cost compliant retrofit, and additional five-year compliance cost across nearest-neighbor configurations for buildings 104777 and 105302.
  ],
) <fig:case-study-costs>

For each case-study building and matching configuration, the compliance premium was calculated as the difference between the modeled cost of the least-cost compliant retrofit and the modeled cost of the least-cost retrofit regardless of compliance. This differs from the additional cost shown in the median and maximum financial sensitivity figures.

The case studies demonstrate that the sensitivity of an investment decision depends not only on changes in predicted emissions, but also on the proximity of those predictions to the regulatory threshold and the relative costs of available retrofit alternatives. These examples evaluate model behavior under alternative matching configurations rather than actual post-retrofit performance.


== Reproducibility and Limitations

The data integration and evaluation pipeline was implemented using dbt, DuckDB, SQL, and Python. Matching diagnostics and emissions sensitivity figures are generated by the project's matching-evaluation script. Financial sensitivity outputs are generated from the analytical
database and exported as CSV and SVG files. All nearest-neighbor comparisons use the same evaluated retrofit options and hold installation costs and applicability fixed while varying the number of matched ComStock simulations. The sensitivity experiments assess the stability of projected emissions, compliance classifications, and investment decisions under alternative model configurations.

Several limitations remain. First, ComStock contains synthetic building simulations rather than observed retrofit outcomes for individual BERDO properties. Second, BERDO disclosure records do not provide complete information about installed building systems, which limits direct validation of retrofit applicability and equipment-specific cost estimates. Third, installation costs are estimated from BTB benchmarks rather than building-specific construction quotes. Finally, the five-year financial comparison excludes energy operating savings, maintenance costs, discounting, and future changes in emissions factors.

Consequently, the results support comparative decision analysis under explicitly stated assumptions, but do not establish guaranteed retrofit performance, future regulatory compliance, or actual construction costs.