
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
  abstract: [Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) requires large buildings to meet increasingly strict greenhouse gas emissions limits, with a major compliance milestone in 2030. This project aims to identify cost-effective decarbonization options for Boston office buildings by considering BERDO disclosures, ComStock building simulations, and Buildings Technology Baseline (BTB) installation cost data. The integrated analysis includes 297 matched office buildings, 81 of which exceed the 2030 emissions standard under BERDO's projected 2030 electricity emissions factor. A data integration pipeline was developed to match BERDO buildings with representative ComStock simulations and estimate potential retrofit emissions reductions. Installation costs, energy bills, and Alternative Compliance Payments (ACP) or climate damages are combined in a 20-year life-cycle cost from 2030 to select one of thirteen retrofit options or ACPs alone for each building, from the owner's and society's perspectives, complemented by a Monte Carlo uncertainty analysis. The resulting framework aims to support investment decisions for office buildings by balancing emissions reductions, compliance requirements, and budget constraints.
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
so somebody has to pick an order. Judging each project on its own savings
doesn't work. A heat pump in a building that was just insulated saves less
than the two estimates added together. And under BERDO, _when_ a building gets
under its limit matters as much as _whether_ it does, since each building has
its own first compliance year and the limits keep tightening after that.

Our goal is to develop a decision-support tool that helps building owners in Boston determine which decarbonization projects to implement and when (@fig:pipeline). The current implementation compares building-level retrofit decisions made at the start of the 2030 compliance period over a 20-year horizon. A budget-constrained, multi-year investment roadmap remains a proposed extension.

= Methods

== Data

This project uses three main publicly available data sources: Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) disclosures, National Lab of the Rockies (NLR) ComStock, and the NLR 2024 Buildings Technology Baseline (BTB). City of Boston building, parcel, and assessing data supply the building geometry that BERDO lacks.

*BERDO* provides building-level information, including property type, gross floor area, energy consumption by fuel, and greenhouse gas emissions @berdo. The analysis focuses on Boston office buildings because these buildings have a relatively high emissions reporting rate. Records are prepared using dbt to standardize property types for storage in DuckDB, convert the fuels BERDO reports in kBtu (natural gas, district energy, and oil/propane) to kWh to match electricity, aggregate related fuel categories, and identify missing or inconsistent values. BERDO provides:
- the observed building characteristics
- baseline emissions for the analysis
- a way to derive ACPs and identify noncompliant buildings

*ComStock* provides simulated commercial building characteristics, baseline energy consumption, and estimates of the impacts of energy-efficiency upgrades @comstock. Our data flow uses the Suffolk County basic annual results and full metadata tables, covering the baseline and the upgrades in @tab:upgrades. Energy measurements are standardized, and weighted energy consumption values are converted to per-building quantities using ComStock simulation weights.

*BTB* provides technology-level performance and installation cost estimates for building efficiency measures @btb. Its commercial dataset contains cost parameters for technologies such as lighting, building envelope improvements, and HVAC equipment. We use these data to estimate the installation costs of the components of the thirteen retrofit options in @tab:upgrades, and of the like-for-like equipment that options without heating and cooling upgrades must eventually replace.

*City of Boston data* give each building's shape. The Planning Department's roof outlines have one polygon per roof section, with a roof height recorded for 2010 @boston-buildings. The city created the outlines from a 2011 flyover and updates them from aerial imagery and LiDAR, so some newer buildings have a footprint but no height. The Assessing Department's 2025 parcels @boston-parcels place each roof section on a parcel, which BERDO identifies by its tax parcel ID. Together they give the story estimates used in matching. The FY2026 property assessment @boston-assessment, keyed by the same parcel ID, gives each building's year built. It is used only to explain missing story estimates (Appendix, Story Estimates).

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

Neither BERDO nor the city's assessor reports stories for commercial buildings, so we estimate them from the city's building roof outlines, which carry roof heights recorded for 2010 @boston-buildings, joined to the 2025 parcels @boston-parcels. A building's stories are its floor area divided by its parcel's footprint when that agrees within a factor of 1.6 with roof height divided by a 13 ft floor-to-floor height, and the height estimate otherwise. The two estimates agree for 218 of the 252 offices with both. Of the 297 offices, 266 receive an estimate; for the other 31 the stories term is zero for every candidate. The appendix (Story Estimates) describes the buildings the method misses.

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
        data.boston.gov roof outlines, roof heights, and parcels;
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
      "20-year cost comparison",
      [
        Thirteen retrofit options and no-retrofit
        alternative, 2030--2049: capital, energy
        bills, and Alternative Compliance Payments
        or climate damages
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


*2030 compliance assessment.* BERDO establishes an office building emissions standard of 3.2 kg $"CO"_2"e"$ per square foot per year for the 2030-2034 compliance period @berdo-standards. For each building and retrofit scenario, estimated emissions are divided by gross floor area and compared with the applicable standard. The electricity portion of each building's emissions follows BERDO's projected grid emissions factor year by year @berdo-grid, net of the Massachusetts Renewable Portfolio Standard Class I share @ma-rps. Together they fall 15% from 2030 to 2034 and 59% by 2049.

The existing data flow's compliance model calculates projected emissions intensity, whether the building meets the standard, and the amount of emissions exceeding the limit. It also includes a no-upgrade scenario representing no retrofit.

For emissions exceeding the limit, BERDO permits ACPs. The current payment rate is \$234 per metric ton of CO#sub[2]e above the emissions limit @berdo-acp. Annual ACP obligations are estimated from the remaining excess emissions in each year after each retrofit scenario, against a limit that steps down to 2.4, 1.6 and 0.8 kg $"CO"_2"e"$ per square foot in 2035, 2040 and 2045 @berdo-standards.


*Cost optimization.* For each building, the no-retrofit alternative and the thirteen retrofit options are compared by their 20-year life-cycle cost from 2030 to 2049, following the global cost method of the EU cost-optimal framework @eu-cost-optimal, which sets a 20-year calculation period for commercial buildings and values equipment left at the end by straight-line depreciation. The cost is the present value of installing each option's components and replacing them at the end of their BTB lifetimes, less their remaining value in 2049, plus each year's energy bills and emissions cost. Options that keep the existing heating and cooling equipment are also charged for replacing it like-for-like when it wears out. Energy bills start from Massachusetts commercial prices @eia-prices @doer-oil and follow the AEO2026 New England projections @aeo.

Two perspectives are compared. The owner pays ACPs on emissions above each year's limit and discounts at a 7% real rate, the return on private capital in OMB's regulatory guidance @omb-a4, reinstated in 2025 @omb-m2515. Society leaves out ACPs, which are a transfer to the city, and instead prices every ton at about \$230 per metric ton of CO#sub[2]e in 2020 dollars @epa-scghg, discounting at 2%, the rate underlying that estimate. Society's electricity emissions follow NLR Cambium's projected ISO-NE grid emission rates @cambium rather than BERDO's factor. For each perspective, the model identifies the lowest-cost option and, separately, the cheapest option that meets the 2030 standard.

*Uncertainty.* The decisions are recomputed at low and high BTB installation costs and under AEO's alternative price cases. A Monte Carlo analysis samples installation costs, energy prices, discount rates (5--9% for the owner, 1--3% for society), and the leave-one-out retrofit-performance errors to estimate how often each recommendation stays the cheapest and compliant.



== Evaluation

We evaluated installation costs, projected greenhouse gas emissions reductions, and 2030 BERDO compliance outcomes across the tested upgrades and packages. The no-retrofit alternative served as the financial baseline for comparing modeled installation and ACP costs.

We examined the lowest-cost overall decision and the lowest-cost compliant retrofit separately, distinguishing financial preference for ACPs from predicted emissions compliance.

BERDO--ComStock matching quality was evaluated using matching distances and differences in building characteristics. Matching configurations (the number of neighbors $k$, inverse-distance weighting, and the district-energy rule) were compared by leave-one-out validation on 618 ComStock office simulations: each simulation's upgrade emissions were predicted from its neighbors and compared with ComStock's result. Two baselines without matching were tested the same way: pooling every other office simulation, and pooling only those of the same size class. Sensitivity analysis then varied k from 1 to 20 and compared the 20-year recommendations and cheapest compliant retrofits against k=20, rebuilding costs, emissions, and ACPs for each k under projected grid emissions and mid prices. For each building over the limit, we also solved for the ACP rate at which a compliant retrofit becomes the owner's cheapest option.

The analysis has several limitations. ComStock represents simulated rather than observed building systems, while BERDO does not provide a complete inventory of existing equipment. Additionally, the emissions projections hold energy use and non-electric emissions factors constant, and electricity follows BERDO's projected factor rather than an observed grid. Installation costs are estimated from technology-level benchmarks rather than building-specific engineering assessments.

The resulting recommendations will therefore be interpreted as preliminary investment estimates for decisions made in 2030 rather than verified retrofit plans.


= Preliminary Results

== Data Exploration and Feasibility

Preliminary exploration focused on assessing the availability and suitability of the BERDO, ComStock, and BTB datasets for the proposed analysis.

The BERDO disclosure provides building-level information on property type, gross floor area, energy consumption, greenhouse gas emissions, and more @berdo. The dataset published for 2026 contains 5,591 building records, a substantial amount for analysis. However, because BERDO relies on self-reported building information, missing and inconsistent values limit the number of usable records. An examination of data completeness across building categories revealed considerable variation, with office buildings exhibiting higher completeness than other building types (@fig:berdo-heatmap).

Of the 5,591 records, 416 buildings with a BERDO ID have Office or Financial Office as their largest property type. Medical Office is left out because BERDO holds it to the separate Healthcare standard. Of these, 185 (44.5%) also contained non-office, non-parking uses, highlighting the frequency of mixed-use properties (@fig:berdo-types). Half of those devote at least 14% of their floor area to other uses. This subset provides a substantial population for the proposed BERDO–ComStock matching procedure, although differences in building composition may introduce additional uncertainty.

To measure the potential need for decarbonization investments, reported greenhouse gas (GHG) emissions intensities were compared against the 2030-2034 BERDO standard for offices of 3.2 kg of $"CO"_2"e"$ per square foot per year @berdo-standards. 300 of the 420 Office and Financial Office records reported GHG intensity values, of which 102 or 34.0% exceeded the 2030 standard (@fig:berdo-GHGvsStandard). This number suggests that a substantial portion of offices might face compliance challenges, highlighting the need for the evaluation of retrofit upgrades and their cost.

ComStock provides baseline simulations and retrofit scenarios with information on building characteristics, fuel consumption, and upgrade applicability @comstock. These variables support the proposed building-matching procedure and estimation of retrofit performance.

Exploration of the BTB commercial dataset identified installation cost information for technologies corresponding to components of the candidate ComStock retrofit packages @btb. Basic package-cost completeness and unit-consistency checks passed. Physical quantities and technology-price assumptions still require validation.


== Integration and Financial Sensitivity

In the integrated analysis, all 297 office buildings were matched to ComStock simulations. Of these, 99 exceed the 2030 emissions standard at today's electricity emissions factor and 81 at BERDO's projected 2030 factor. At k=20, 71 of those 81 buildings had at least one predicted compliant retrofit among thirteen tested options. Over 20 years under projected grid emissions and prices, a retrofit is cheaper than no retrofit for all 81 buildings from both perspectives, and the cheapest option meets the standard for 36 buildings from the owner's perspective and 41 from society's. The owner's cheapest option is most often rooftop PV with roof insulation (Package 12, 46 buildings, 13 of them compliant). Heat pump options are chosen for 18 buildings by the owner and 27 by society. The owner's choice is the same at low, mid, and high BTB installation costs for 41 of the 81 buildings, and society's for 62.

Which matters more, energy prices or how BERDO counts electricity? Of the 99 offices over the limit at today's factor, 18 fall under it in 2030 without a retrofit, only because BERDO's projected factor counts each kilowatt-hour as cleaner @berdo-grid. Prices barely move the answer. With BERDO's factor held at today's level, switching from today's prices to the AEO baseline changes the owner's compliant picks from 42 to 43 of 99. Across AEO's alternative cases, from expensive gas to data-center demand, the owner's cheapest option meets the standard for 34 to 37 of the 81 offices still over the limit, against 36 in the baseline.

How high would the ACP have to be? Every ton over the limit costs the owner the ACP each year, so a higher rate makes compliance cheaper by comparison. For each office over the limit, we found the rate at which a compliant retrofit becomes the owner's cheapest option (@fig:breakeven). Of the 71 offices that have one, 26 would pick it with no ACP at all, and 36 already do at \$234. Another 17 tip below \$1,000 per ton. The last 18 need more than that, five of them more than \$10,000. The other 10 offices have no compliant option among our thirteen, so no rate gets them under the limit.

How stable are these picks? Across 5,000 Monte Carlo draws, the owner's recommendation stays the cheapest in 74% of draws for the average office, and society's in 80%. It holds in at least 90% of draws for 20 offices from the owner's view and 41 from society's, and in fewer than half for 12 and 10.

One building makes this concrete. 24--32 Farnsworth Street (BERDO 106476) is a 78,860 sq ft office in Fort Point that gets 65% of its energy from natural gas. It reports 4.8 kg $"CO"_2"e"$ per square foot, well over the 2030 limit of 3.2. From both the owner's and society's view, its cheapest 20-year option is Package 2, LED lighting with heat pumps, which keeps it under the limit through 2044. Package 4, the same retrofit with a standard-efficiency rooftop heat pump, ties it exactly. Over 20 years, Package 2 saves the owner about \$270,000 against paying ACPs, and society about \$980,000. The owner's cheapest option that stays over the limit, wall insulation, costs about \$150,000 more.

Matching is worth doing. At k=20 the leave-one-out mean absolute error is 6.58 percentage points of emissions reduction, against 8.20 when every other office simulation is pooled and 7.98 when only those of the same size class are. Matching beats pooling by 1.62 points (95% CI 1.36--1.89) and does better for 78% of the held-out simulations.

In leave-one-out validation, adding stories to the distance lowered the mean absolute error at k=20 from 7.05 to 6.58 percentage points of emissions reduction, and the median from 3.80 to 3.00, though the 90th percentile rose from 18.08 to 18.83. Inverse-distance weighting with the district-energy rule remained the best configuration tested, within 0.01 points of its minimum at k=19. Compared with unweighted matching without the rule at the same k, it was 0.10 points better (95% CI 0.01--0.19), and 0.21 points better for district-energy simulations, a borderline difference (95% CI 0.003--0.41). Held-out simulations have their exact story counts, while BERDO buildings have estimates, so the stories term likely helps less in practice.

The error is not even across upgrades. Heat pump options are the hardest to predict: VRF and geothermal miss by about 14--15 points on average cuts of 20--26%, and Packages 2 and 5 by about 10 points on cuts of 18--20%. Single envelope, lighting, and PV measures miss by 1--3 points. Individual heat pump estimates should be read as rough.

Compared with k=20, the owner's cheapest compliant retrofit changed for 40 of 69 commonly eligible buildings at k=1, 18 of 70 at k=10, and 6 of 71 at k=19. For society, it changed for 31, 14, and 4. Some of these changes matter less than they look. Three of the 18 at k=10 are swaps between Packages 2 and 4, which differ only in the efficiency of the rooftop heat pump and have identical 20-year costs for 49 of the 297 offices.

Two buildings illustrate this sensitivity. For building 104777 (160-170 State Street, Boston), Package 2 was the owner's cheapest compliant retrofit at most k, but Package 5 at k=1 and 4. For building 105302 (2-16 Tremont Street, Boston), roof insulation was the cheapest compliant option at k=1-2, Package 4 at k=3, Package 2 at k=4-13, and wall insulation from k=14 on.

These findings demonstrate sensitivity of investment recommendations to neighbor selection, particularly near compliance thresholds.


== Current Limitations

The preliminary BERDO analysis revealed some data quality limitations. Of the 420 Office and Financial Office records, 120 (28.6%) lack reported GHG emissions intensity data, limiting the coverage of the 2030 compliance assessment.

Additionally, the selected buildings set contains both single-use office buildings and mixed-use buildings where offices account for the largest part. For mixed-use spaces, reported energy consumption and emissions data may reflect the use of spaces other than offices, which introduces some uncertainty in matching these buildings to ComStock simulations. Verifying the distribution of energy consumption on each building would require property-level information, potentially from individual building owners or management companies, which is beyond the scope of this project.

The integration and matching sensitivity models have been evaluated for internal consistency and robustness to k. However, observed post-retrofit outcomes are unavailable, so predictive accuracy remains unverified. Installation costs and building-level 20-year cost comparisons have been calculated, but cost assumptions require further validation: the existing equipment's type and age are inferred rather than observed, and incentives such as Mass Save rebates are not included. Multi-year optimization currently remains outside the implemented scope.

The grid assumptions are policy, not physics. BERDO's Review Board reviews the projected factors at least every five years and may change them @berdo-grid, and the RPS rises 1% a year after 2030 only "unless modified by law" @ma-rps. Cambium 2024 was published before the 2025 changes to federal clean-energy tax credits, so society's grid may be cleaner than the one Boston actually gets. Society's view also rests on a number the federal government no longer uses. Since May 2025, it has not been federal policy to maintain a uniform estimate of greenhouse gas damages @omb-m2527, so the \$230 per ton is the EPA's 2023 estimate, not a current one.

// ---- 9: discussion --------------------------------------------------------

= Discussion

Preliminary exploration of the BERDO dataset highlighted the importance of data completeness in providing reliable building decarbonization recommendations. Although office buildings exhibited relatively high data completeness, records with missing data and the presence of mixed-use properties can introduce potential uncertainty to the analysis. These findings suggest that further investigation of data quality and matching reliability can improve the results.

We evaluated BERDO--ComStock matching using building-characteristic differences and sensitivity to the number of nearest neighbors. Retrofit recommendations changed for some buildings when k varied, particularly where predicted emissions were close to the compliance threshold. Comparing neighbor aggregation methods led us to weight neighbors by inverse distance and to match district-energy buildings only to district-energy simulations, and adding stories estimated from city building footprints and roof heights reduced the leave-one-out error further.

Missing data remains a problem in its own right. 120 of the 420 office records report no GHG intensity. Some of these could be filled from related fields, and imputation could cover the rest, though only as well as the predictors allow.

Our approach now includes energy bills alongside installation costs over a 20-year horizon, following the EIA's _Annual Energy Outlook_ @aeo price scenarios. Charging every option for its replacements and remaining value over the same horizon, and charging options that keep existing equipment for its like-for-like replacement, avoids penalizing long-lived electrification measures. BERDO's flat ACP per ton remains the main barrier to deeper retrofits, since it gives no extra reward for meeting the standard. At today's \$234, the owner's cheapest option meets the standard for 36 of 81 buildings, against 41 when society's climate damages are counted instead. Raising the rate to \$1,000 would bring the owner's count to 53, but 18 offices would still need more, and 10 have no compliant option at any price.

Where next? Our first priority is confidence in the predicted outcomes, not more financial detail. The leave-one-out test checks simulations against simulations. Checking against real retrofits would need engineering studies, or BERDO disclosures from buildings before and after an upgrade. Second, the 10 offices without a compliant option need more to test: more ComStock upgrades, priced from BTB. Third, time. The model makes one decision in 2030 and holds equipment prices fixed. Letting costs change year by year, and choosing what to retrofit and when under a budget, is the multi-year roadmap we set out to build.

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
    width: 80%,
  ),
  caption: [
    Completeness of selected BERDO attributes for the five most common building uses, with Office and Financial Office combined. Each cell is the percentage of records with a value for the corresponding variable.
  ],
) <fig:berdo-heatmap>

#figure(
  image(
    "figures/berdo-mixed-use-cdf.png",
    width: 80%,
  ),
  caption: [
    Cumulative distribution of the mixed-use share, the share of non-parking floor area in uses other than office, across the 416 BERDO buildings whose largest property type is Office or Financial Office. The jump at 0% is the buildings with only office and parking space.
  ],
) <fig:berdo-types>

#figure(
  image(
    "figures/berdo-intensity-cdf.png",
    width: 80%,
  ),
  caption: [
    Cumulative distribution of reported greenhouse gas emissions intensity for the 300 Office and Financial Office records that report it, compared with the 2030 BERDO office standard.
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

== Story Estimates

Stories come from the city's roof outlines, whose heights are recorded for 2010 @boston-buildings, placed on the 2025 parcels @boston-parcels. Of the 297 offices, 218 use floor area over footprint, confirmed by roof height; 45 use roof height, because the two disagree or the parcel holds more than one BERDO building; 3 use floor area over footprint with no height to check it; and 31 have no estimate.

The outlines have been updated since 2010, but the newer footprints carry no height. These skew new. By the FY2026 assessor's year built @boston-assessment, 41 of the 110 BERDO buildings whose footprint has no measured height and whose year is known (37%) were built in 2010 or later, against 7% of buildings with a measured height. Their floor-area estimate is used unchecked, which fails when the parcel holds only a fragment of a building. BERDO 104376, built in 1914, has 110,005 sq ft over a 175 sq ft fragment, or 630 stories. An unchecked estimate above 60 stories, the height of Boston's tallest building, is therefore discarded, and 104376 joins the offices without an estimate. Its matches and recommendations are the only ones affected. At $k = 20$, the owner's cheapest option moved from VRF to Package 5 and society's from VRF to Package 12; none of them meets the 2030 standard.

The other 30 offices without an estimate have no roof section on their parcel. For 16, the parcel ID, a condominium or sub-parcel ID that does not end in 000, has no polygon in the 2025 parcel layer. For the other 14, no roof section's interior point falls inside the parcel, so their building is counted toward neighboring parcels. These are not mainly new buildings: the median year built is 1951, and 13 of the 26 with a year were built before 1920. They are matched on size, EUI, and fuel shares alone.

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

== 20-Year Global Cost

Each option is costed over $N = 20$ years from 2030 ($t = 1$ is 2030) at discount rate $rho$, 0.07 for the owner and 0.02 for society. A component $m$ with installed cost $K_m$ and BTB lifetime $L_m$ is installed at the start and replaced every $L_m$ years, and its last installation is credited its straight-line remaining value at the horizon:

$
  V_m = K_m (sum_(j=0)^(J_m) (1 + rho)^(-j L_m) - lambda_m (1 + rho)^(-N))
$

where $J_m$ is the last $j$ with $j L_m < N$ and $lambda_m = ((J_m + 1) L_m - N) \/ L_m$ is the share of the last installation's life left at the horizon. Existing heating and cooling equipment $e in H_b$ is valued the same way, with each replacement delayed by its remaining life. The global cost is

$
  C_(b,p) = & sum_(m in p) V_m + bb(1)_p sum_(e in H_b) V_e \
            & + sum_(t=1)^N (E_(b,p,t) + P_(b,p,t)) / (1 + rho)^t
$

where $bb(1)_p$ is one for options that keep the existing equipment. The energy bill is $E_(b,p,t) = sum_f Q_(b,f) r_(b,p,f) c_f pi_(f,t)$, with $Q_(b,f)$ the building's reported use of fuel $f$, $c_f$ its 2025 price, and $pi_(f,t)$ the AEO price index (2025 = 1). The owner's emissions cost is the ACP, $P_(b,p,t) = 0.234 max(0, G_(b,p,t) - S_t A_b)$, where $S_t$ is the standard in force in year $t$ and $A_b$ is floor area. Society's is $P_(b,p,t) = 0.230 tilde(G)_(b,p,t)$, where $tilde(G)$ replaces BERDO's electricity factor index $e_y$ with Cambium's grid emission rate index. Both rates are in dollars per kilogram. Operation and maintenance costs are left at zero, since BTB gives none.

== Break-Even ACP

From the owner's view, an option's 20-year cost is linear in the ACP rate $a$: $C_(b,p)(a) = F_(b,p) + a T_(b,p)$, where $T_(b,p)$ is the present value of its tons over the limit and $F_(b,p)$ is everything else. A compliant option beats another wherever its line is lower. An office's break-even rate is the lowest $a$ at which some compliant option beats every other option, compliant or not (@fig:breakeven).

#figure(
  image(
    "figures/breakeven-acp.png",
    width: 80%,
  ),
  caption: [
    Over-limit offices whose cheapest 20-year option, from the owner's view, meets the 2030 standard, as the ACP rate rises (projected grid emissions and prices, BTB mid costs). Each step is one office's break-even rate. Global cost is linear in the rate, so each break-even rate is found exactly.
  ],
) <fig:breakeven>
