
// Optimizing Decarbonization Investment Decisions for Boston Office Buildings
// Build from the repository root: typst compile --root . "report-2/report 2.typ"

#import "@preview/charged-ieee:0.1.4": ieee
#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node
#import "@preview/zero:0.6.1": num, set-group, set-num, set-round, ztable

// Computed numbers: three significant figures, text font, commas only in integers.
#set-num(math: false)
#set-round(mode: "figures", precision: 3)
#set-group(separator: ",", threshold: (integer: 4, fractional: calc.inf))

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
        Industry Stakeholder: Debra Shepard, Founder & Principal Consultant, Riverstone Sustainability
      ],
    ),
  ),
  abstract: [Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) requires large buildings to meet increasingly strict greenhouse gas emissions limits, with a major compliance milestone in 2030. This project aims to identify cost-effective decarbonization options for Boston office buildings by considering BERDO disclosures, ComStock building simulations, and Buildings Technology Baseline (BTB) installation cost data. The integrated analysis includes 297 matched office buildings, 81 of which exceed the 2030 emissions standard under BERDO's projected 2030 electricity emissions factor. A data integration pipeline was developed to match BERDO buildings with representative ComStock simulations and estimate potential retrofit emissions reductions. Installation costs, energy bills, and Alternative Compliance Payments (ACP) or climate damages are combined in a 20-year life-cycle cost over 2027--2046 to select among 23 retrofit options and a no-retrofit baseline for each building, from the owner's and society's perspectives, complemented by a Monte Carlo uncertainty analysis. The resulting framework aims to support investment decisions for office buildings by balancing emissions reductions, compliance requirements, and long-term investment costs.
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
zero by 2050 (Appendix, @fig:berdo-limits) @berdo. The owner of one of these buildings, say an office, has a list of candidate
projects: heat pumps, envelope upgrades, LED retrofits, rooftop solar,
switching off fuel oil, etc. If a retrofit is not economical, the owner can instead make an _Alternative Compliance Payment_ (ACP). Are ACPs a strong enough incentive to drive decarbonization?

Owners might lack the capital to do all of the updates at once. Judging each project on its own savings doesn't work. A heat pump in a building that was just insulated saves less than the two estimates added together. Which investment minimizes an owner's long-term costs, and will the cheapest choice meet the 2030 BERDO emissions standard? The owner weighs installation costs, energy bills, and ACPs on emissions above the limit. The societal comparison values climate damage from every ton, so it can favor a different retrofit.

Luddeni et al. combined building-stock simulation with cost-optimal retrofit selection for Italian offices @luddeni-office-retrofits, and the EU framework compares packages by discounted life-cycle cost for reference buildings @eu-cost-optimal. Applying these methods to individual Boston offices requires linking three data sources. BERDO reports actual energy use and emissions without showing how a building would perform after a retrofit @berdo @berdo-standards. ComStock simulates those effects for synthetic buildings with no direct match to BERDO records @comstock. Buildings Technology Baseline (BTB) installation costs must be assigned to applicable measures and scaled to each building @btb.

We use constrained $k$-nearest-neighbor matching to find comparable simulations, estimate energy and emissions changes with fuel-specific ratios, and map retrofit components to BTB costs. We compare 23 retrofits and no retrofit for one decision in 2027, using global costs over 2027--2046 from owner and societal perspectives (Appendix, @fig:pipeline). We evaluate matching accuracy, sensitivity, and uncertainty. A staged, budget-constrained investment roadmap remains future work.

= Methods

== Data

This project uses three main publicly available data sources: Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) disclosures, National Lab of the Rockies (NLR) ComStock, and the NLR 2024 Buildings Technology Baseline (BTB). City of Boston building, parcel, and assessing data supply the building geometry that BERDO lacks.

*BERDO* provides building-level information, including property type, gross floor area, energy consumption by fuel, and greenhouse gas emissions @berdo. The analysis focuses on Boston office buildings because these buildings have a relatively high emissions reporting rate. Records are prepared using dbt to standardize property types for storage in DuckDB, convert the fuels BERDO reports in kBtu (natural gas, district energy, and oil/propane) to kWh to match electricity, aggregate related fuel categories, and identify missing or inconsistent values. BERDO provides:
- the observed building characteristics
- baseline emissions for the analysis
- a way to derive ACPs and identify noncompliant buildings

*ComStock* provides simulated commercial building characteristics, baseline energy consumption, and estimates of the impacts of energy-efficiency upgrades @comstock. Our data flow uses the Suffolk County basic annual results and full metadata tables, covering the baseline and the upgrades in @tab:upgrades. Energy measurements are standardized, and weighted energy consumption values are converted to per-building quantities using ComStock simulation weights.

*BTB* provides technology-level performance and installation cost estimates for building efficiency measures @btb. Its commercial dataset contains cost parameters for technologies such as lighting, building envelope improvements, and HVAC equipment. We use these data to estimate the installation costs of the components of the 23 retrofit options in @tab:upgrades, and of the like-for-like equipment that options without heating and cooling upgrades must eventually replace.

*City of Boston data* give each building's shape. The Planning Department's roof outlines have one polygon per roof section, with a roof height recorded for 2010 @boston-buildings. The city created the outlines from a 2011 flyover and updates them from aerial imagery and LiDAR, so some newer buildings have a footprint but no height. The Assessing Department's 2025 parcels @boston-parcels place each roof section on a parcel, which BERDO identifies by its tax parcel ID. Together they give the story estimates used in matching. The FY2026 property assessment @boston-assessment, keyed by the same parcel ID, gives each building's year built. It is used only to explain missing story estimates (Appendix, Story Estimates).

== Data Integration and Optimization

*Building matching.* BERDO and ComStock cannot be joined directly by building identifier because BERDO represents real buildings, while ComStock contains synthetic building simulations. We use k-nearest-neighbor (KNN) matching to borrow retrofit effects from the $k$ most similar eligible ComStock models for each BERDO office @berdo @comstock.

First, a property-type crosswalk restricts candidate ComStock models to building types compatible with each BERDO property type. Then similarity is calculated using gross floor area, site energy use per unit of floor area (energy use intensity, or EUI), fuel-consumption shares, and number of stories.

The distance function combines the absolute logarithmic differences in building size, EUI, and stories with half the sum of absolute differences in fuel shares:

$
  d(b,c) & = abs(ln(A_b / A_c)) \
         & + abs(ln("EUI"_b / "EUI"_c)) \
         & + 0.5 sum_f abs(s_(b,f) - s_(c,f)) \
         & + abs(ln(S_b / S_c))
$

Here $A$ is floor area, $S$ is the story count, and $s_f$ is the share of energy from fuel $f$. The three absolute log ratios measure proportional differences on the same scale. We use unit coefficients for the three logarithmic differences and a coefficient of 0.5 for the sum of fuel-share differences. The coefficients are heuristic rather than systematically optimized. Halving the sum of fuel-share differences avoids counting a shift from one fuel to another twice and bounds that term between zero and one.

Neither BERDO nor the city's assessor reports stories for commercial buildings, so we estimate them from the city's building roof outlines, which carry roof heights recorded for 2010 @boston-buildings, joined to the 2025 parcels @boston-parcels. A building's stories are its floor area divided by its parcel's footprint when that agrees within a factor of 1.6 with roof height divided by a 13 ft floor-to-floor height, and the height estimate otherwise. The two estimates agree for 218 of the 252 offices with both. Of the 297 offices, 266 receive an estimate; for the other 31 the stories term is zero for every candidate. The appendix (Story Estimates) describes the buildings the method misses.

We rank eligible simulations by distance and retain the $k$ closest.

We match only simulations with the same district-energy use status. This preserves a district-fuel baseline for district-heated offices. We use $k = 20$ because its validation error is near the minimum and recommendations change less as $k$ approaches 20 (@tab:matching-validation and @fig:k-sensitivity). We pool the neighbors with inverse-distance weights $w_(b c) = 1 \/ (d(b,c) + 10^(-6))$.

*Retrofit performance estimation.* ComStock baseline and upgrade scenarios are linked using their synthetic building identifiers. For each BERDO building and upgrade, the ratio of total upgraded to baseline energy consumption, weighted by $w_(b c)$, is calculated separately for electricity, natural gas, oil/propane, district heating, and district cooling across the matched simulations. The 23 retrofit options considered are listed in Appendix @tab:upgrades.

The fuel-specific ratios are applied to the corresponding BERDO building's observed energy consumption and greenhouse gas emissions. This approach preserves the building's reported emissions baseline and fuel-specific emissions factors while transferring the modeled effects of ComStock upgrades.

If the matched simulations have no baseline consumption for a particular fuel, its ratio is set to one, leaving that fuel unchanged. Upgrade applicability is also summarized across the matched simulations. Because BERDO does not contain a complete inventory of installed equipment, the estimated impacts represent modeled retrofit opportunities rather than verified building-specific improvements.

*Installation cost estimation.* Selected ComStock upgrades and packages are mapped to corresponding BTB technologies @btb. Installation costs are estimated from applicable component quantities and BTB unit prices, with building-level scaling where appropriate. Low, mid, and high cost estimates are retained. Options that keep the existing heating and cooling equipment are also charged for replacing it like-for-like with gas rooftop units and boilers, sized from the matched simulations; heat pump, VRF, and geothermal options replace it instead. All costs are in 2025 dollars, converted with the GDP price deflator @bea-deflator: BTB's from 2023 dollars, and the PV, ground-loop, and economizer costs from their sources' years.

The pipeline is written as SQL models in dbt, a data transformation tool @dbt, and its workflow is summarized in Appendix @fig:pipeline.


*2030 compliance assessment.* BERDO establishes an office building emissions standard of 3.2 kg $"CO"_2"e"$ per square foot per year for the 2030-2034 compliance period @berdo-standards. For each building and retrofit scenario, estimated emissions are divided by gross floor area and compared with the applicable standard. The electricity portion of each building's emissions follows BERDO's projected grid emissions factor year by year @berdo-grid, net of the Massachusetts Renewable Portfolio Standard Class I share @ma-rps. The resulting net factor falls 12% from 2027 to 2030 and 58% from 2027 to 2046.

For emissions exceeding the limit, BERDO permits ACPs. The current payment rate is \$234 per metric ton of CO#sub[2]e above the emissions limit @berdo-acp, which we hold constant in 2025 dollars. Annual ACP obligations are estimated from the remaining excess emissions in each year after each retrofit scenario, against a limit of 5.3 kg $"CO"_2"e"$ per square foot through 2029 and 3.2 from 2030, stepping down to 2.4, 1.6 and 0.8 in 2035, 2040 and 2045 @berdo-standards.


*Cost optimization.* We compare no retrofit and 23 retrofit options over 2027--2046 using the EU global cost method for commercial buildings @eu-cost-optimal. Global cost is the present value of installation, replacement, energy bills, and emissions costs, less the straight-line residual value of equipment in 2046. Options that keep existing HVAC include like-for-like replacement. Massachusetts commercial energy prices @eia-prices @doer-oil follow AEO2026 New England projections @aeo. Owner costs include any ACPs owed from 2027 onward. A compliant option meets the modeled 2030 emissions limit before ACPs.

Two perspectives are compared. The owner pays ACPs on emissions above each year's limit and discounts at a 7% real rate, the return on private capital in OMB's regulatory guidance @omb-a4, reinstated in 2025 @omb-m2515. Society leaves out ACPs, which are a transfer to the city, and instead prices every ton at about \$230 per metric ton of CO#sub[2]e in 2020 dollars (\$281 in 2025 dollars) @epa-scghg, discounting at 2%, the rate underlying that estimate. Society's electricity emissions follow NLR Cambium's projected ISO-NE grid emission rates @cambium rather than BERDO's factor. For each perspective, the model identifies the lowest-cost option and, separately, the cheapest option that meets the 2030 standard.

*Uncertainty.* The decisions are recomputed at low and high BTB installation costs and under AEO's alternative price cases. A Monte Carlo analysis samples installation costs, energy prices, discount rates (5--9% for the owner, 1--3% for society), and the leave-one-out retrofit-performance errors to estimate how often each recommendation stays the cheapest.


== Evaluation

Leave-one-out validation hides each of 618 ComStock offices in turn and compares its simulated retrofit reductions with predictions from the remaining simulations. We compare neighbor counts, weighting, and district-energy rules with pooling across all other offices or the same size class. We also compare 20-year cost rankings for $k = 1$ through 20 and estimate the owner's break-even ACP where a compliant option exists.

The recommendations are investment estimates for a decision made in 2027, not verified retrofit plans. @sec:limitations covers what these checks cannot tell us.


#let scenario-summary = csv("../dbt/analysis_outputs/energy_scenario_outcomes.csv", row-type: dictionary)
#let projected-owner = scenario-summary.find(r => r.scenario == "projected" and r.perspective == "financial")
#let at-risk-count = int(projected-owner.offices) - int(projected-owner.under_limit_anyway)

= Results

== BERDO Coverage

The 2026 BERDO disclosure has 5,591 building records @berdo. Owners report their own data, so completeness varies a lot by building type, and offices are among the most complete (Appendix, @fig:berdo-heatmap). 416 buildings with a BERDO ID have Office or Financial Office as their largest property type. Medical Office is left out because BERDO holds it to the separate Healthcare standard. 185 of the 416 (44.5%) also have non-office, non-parking space, and half of those give at least 14% of their floor area to other uses (Appendix, @fig:berdo-types).

Only 297 of the 416 (71%) report GHG emissions, and those 297 are the offices we analyze. At today's electricity factor, the model puts 99 of them (33%) above the 2030 office standard of 3.2 kg $"CO"_2"e"$ per square foot @berdo-standards. The distribution of reported intensities is in Appendix @fig:berdo-GHGvsStandard. A third of reporting offices is a lot of buildings with a decision to make before 2030.

== Matching Accuracy

Matching is worth doing. At $k = 20$, the mean absolute error (MAE), the average size of the prediction error regardless of sign, is 6.65 percentage points of emissions reduction. Pooling all other offices gives 7.55 points and pooling the same size class gives 7.45 (Appendix, @tab:matching-validation). Adding stories to the distance lowered the MAE from 6.92 to 6.65 points and the median error from 3.32 to 2.82, though the 90th percentile rose from 19.3 to 19.9 (Appendix, @tab:feature-analysis).

== Recommendations

Under projected grid factors, baseline energy prices, and mid installation costs, 81 offices exceed the 2030 limit without a retrofit and 71 have a modeled compliant option. A retrofit is cheapest at all 81 from both perspectives. The societal optimum is compliant at 11 more offices than the owner optimum (@fig:compliance-outcomes). Compared with no retrofit, the cheapest 20-year options save owners \$39.0 million and society \$103 million in total. Package 12, rooftop PV with roof insulation, is the most common choice from both perspectives (28 owner picks and 40 societal picks).

#figure(
  image("figures/compliance-outcomes.svg", width: 94%),
  caption: [Modeled 2030 compliance of minimum-global-cost retrofits for the #at-risk-count at-risk offices, by perspective. Both sets are evaluated against the BERDO limit under projected conditions.],
  placement: bottom,
) <fig:compliance-outcomes>

One building makes this concrete. 24--32 Farnsworth Street (BERDO 106476) is a 78,860 sq ft office in Fort Point that gets 65% of its energy from natural gas. It reports 4.8 kg $"CO"_2"e"$ per square foot, well over the 2030 limit of 3.2. From both the owner's and society's view, its cheapest 20-year option is the electric-backup heat pump boiler. It meets the 2030 standard and saves the owner \$261,000 and society \$1.26 million compared with no retrofit (Appendix, @tab:farnsworth-results).

BERDO's projected electricity factor brings 18 of the 99 offices below the 2030 limit without a retrofit @berdo-grid. Among the remaining 81, the owner's cheapest option is compliant for 35 to 37 offices across the AEO price cases.

Of the 71 offices with a compliant option, 29 would choose one at a zero ACP, 35 at \$234, and 50 at \$1,000 per metric ton (@fig:breakeven).

#figure(
  image(
    "figures/breakeven-acp.png",
    width: 100%,
  ),
  caption: [
    Over-limit offices whose cheapest 20-year option, from the owner's view, meets the 2030 standard, as the ACP rate rises (projected grid emissions and prices, BTB mid costs). The curve counts offices by the first rate at which a compliant option is cheapest and shows rates up to \$2,000 per metric ton. Break-even rates are calculated from the cost-line intersections and rounded to cents.
  ],
  placement: none,
) <fig:breakeven>

Across 5,000 Monte Carlo draws per office, recommendation stability is the fraction of draws in which the original option remains cheapest. Under projected conditions, the averages are 75.0% for owners and 80.2% for society. Compliance confidence instead measures how often that option meets the limit in a given year (Appendix, @sec:additional-results).

== Sensitivity to the Number of Neighbors

Compared with $k = 20$, the owner's cheapest compliant choice changes for 34 of 69 offices eligible at both settings at $k = 1$, 15 of 70 at $k = 10$, and 2 of 71 at $k = 19$. For both perspectives, fewer recommendations generally differ from the reference as $k$ approaches 20 (@fig:k-sensitivity).

#figure(
  image("figures/global-k-sensitivity.svg", width: 78%),
  caption: [Changes in the lowest 20-year cost recommendations relative to $k = 20$ for the #at-risk-count at-risk offices. The compliant comparison includes only offices with a compliant option at both neighbor counts. Projected conditions and mid costs. Source: dbt 20-year neighbor-sensitivity output.],
  placement: bottom,
  scope: "parent",
) <fig:k-sensitivity>


// ---- 9: discussion --------------------------------------------------------

= Discussion

Did we meet our goals? Partly. We set out to help owners decide which projects to do and when, and to ask whether ACPs are a strong enough incentive. The first and last we can answer. For each of the 81 offices over the limit, the model gives the cheapest 20-year option from the owner's and society's view, and at \$234 per ton the ACP is not enough to make compliance the owner's cheapest choice for most of them. We did not get to the "when." The model makes one decision in 2027, so it cannot say whether to insulate first and add heat pumps later, even though the order matters.

Three results stand out. First, matching improves on pooling, though heat pump estimates remain rough. Second, the projected electricity factor has a larger effect on 2030 compliance than the AEO price cases. Third, owners face ACPs only on excess emissions, while society counts damages from every ton. That difference helps explain why more societal recommendations meet the limit. Raising the ACP to \$1,000 would make compliance cheapest for 50 owners, but 10 offices have no compliant option in the modeled portfolio.

== Limitations <sec:limitations>

*We validated against simulations, not buildings.* The leave-one-out test asks how well one ComStock simulation predicts another. We have no observed post-retrofit outcomes, so how closely a real office would track its prediction is unknown. That matters most where the model leans hardest. For 51 of the 71 offices with a compliant option, the owner's cheapest compliant option is a heat pump option, with 4--15 points of error depending on the upgrade. Those recommendations are only as good as that error allows.

*The match cannot see a building's HVAC system.* BERDO and the assessor lack commercial HVAC labels. Simulated story counts are exact, while BERDO story counts are estimated and missing for 31 offices. The distance coefficients were not systematically optimized.

*BERDO is self-reported.* 119 of the 416 offices report no GHG emissions, so they are not in the compliance analysis at all. If those buildings differ from the ones that report, the count of 81 offices over the limit is biased, and we cannot tell in which direction. Mixed use adds noise. BERDO reports energy for the whole building, so an office with a restaurant on the ground floor is matched as if it were all office. Splitting that out would take property-level data from owners.

*Costs are benchmarks.* Installation costs come from BTB technology prices, scaled by the matched simulations' equipment sizes, not from engineering estimates for a specific building. The type and age of existing equipment are inferred from the matched simulations rather than observed. Equipment prices are BTB's 2030 projection, its nearest to 2027, held for all 20 years. BTB estimates represent gross installation costs. Excluding incentives such as Mass Save rebates may overstate the net investment cost to building owners.

*The grid assumptions are policy, not physics.* BERDO's Review Board reviews the projected factors at least every five years and may change them @berdo-grid, and the RPS rises 1% a year after 2030 only "unless modified by law" @ma-rps. Cambium 2024 was published before the 2025 changes to federal clean-energy tax credits, so society's grid may be cleaner than the one Boston actually gets. Society's \$230 per ton uses the EPA's 2023 estimate. In May 2025, OMB directed agencies to limit consideration of GHG emissions in regulatory and permitting decisions @omb-m2527.

*One decision, once.* The model picks one option in 2027 and holds it for 20 years. It cannot stage work (insulation now, heat pumps when the boiler fails), respect a budget, or plan across a portfolio of buildings. Energy use apart from the retrofit's effect is held constant. And 10 of the 81 offices have no compliant option among the 23 we tested, so for them the model can only say which partial retrofit costs least.

== Next Steps

Our first priority is confidence in the predicted outcomes, not more financial detail. Simulated HVAC labels improve leave-one-out predictions in our sensitivity test (@sec:feature-matching). Building permits are one candidate source. Checking against real retrofits would need engineering studies, or BERDO disclosures from buildings before and after an upgrade. Second, the 10 offices without a compliant option. The expanded portfolio offers no compliant option for these offices, and even Package 3, heat pumps with a full envelope retrofit, leaves them over the limit. Seven get within 0.65 kg CO#sub[2]e/ft#super[2]/year of the standard with their best option, close enough that renewable energy purchases, which BERDO allows but we do not model, might close the gap. The other three stay at 5.3 to 6.8 kg CO#sub[2]e/ft#super[2]/year. Third, time. Letting costs change year by year, and choosing what to retrofit and when under a budget, is the multi-year roadmap we set out to build.

// ---- 10: statement of contributions ---------------------------------------

= Statement of Contributions

*Konstantinos Theodoropoulos:* stakeholder communication; BERDO data exploration and validation; inverse-distance weighting evaluation and dbt integration; attending office hours with Dr. Bemis.

*Zachary Wegrzyniak:* data pipeline in dbt and DuckDB (ComStock and BERDO join, mixed-use evaluation); editing; repo setup.

*Kateryna Lysytsyna:* ComStock exploration and retrofit selection; BTB–ComStock cost integration and validation; expansion to 23 retrofit options; BERDO–ComStock matching evaluation; emissions, compliance, and financial sensitivity analyses; 20-year Monte Carlo uncertainty analysis; visualizations.

= AI Use Disclosure

Claude Opus 5.5 and ChatGPT 6.1 were used for data retrieval, portions of the data pipeline, typesetting, visualizations, and editing.

// ---- 11: references -------------------------------------------------------

#pagebreak()
#bibliography("refs.yml")

// ---- 12: appendix ---------------------------------------------------------

#show figure.caption: set align(center)

= Appendix

This appendix provides the data flow (@fig:pipeline), the BERDO data diagnostics cited in the main report, the matching validation, the story estimates, the cost and break-even ACP equations, and supporting results. The source code and reproducibility scripts are available at
#link("https://github.com/wegry/DS5500")[github.com/wegry/DS5500].

== Retrofit Options

#let retrofit-groups = (
  (
    [Individual measures],
    (
      (43, [LED lighting], [LED lighting]),
      (48, [Wall insulation], [Exterior wall insulation]),
      (49, [Roof insulation], [Roof insulation]),
      (52, [New windows], [High-performance windows]),
      (12, [VRF], [VRF with dedicated outdoor air]),
      (29, [Geothermal], [Ground-source HP]),
      (46, [Rooftop PV], [Photovoltaics on 40% of the roof]),
      (19, [Economizers], [Air-side economizers]),
      (20, [DCV], [Demand-controlled ventilation]),
      (21, [Energy recovery], [Air-handler energy recovery]),
      (15, [HP boiler], [Electric backup]),
    ),
  ),
  (
    [Heat pump RTU upgrades],
    (
      (1, [Variable HP RTU], [Electric backup]),
      (2, [Variable HP RTU], [Original-fuel backup]),
      (4, [Standard HP RTU], [Electric backup]),
      (3, [HP RTU + ER], [Variable-speed HP RTU; energy recovery]),
      (6, [HP RTU + roof], [Standard HP RTU; roof insulation]),
      (7, [HP RTU + windows], [Standard HP RTU; new windows]),
    ),
  ),
  (
    [Packages],
    (
      (54, [Package 1], [Wall and roof insulation; new windows]),
      (55, [Package 2], [LED lighting; variable-speed HP RTU or HP boiler]),
      (56, [Package 3], [Packages 1 and 2 combined]),
      (57, [Package 4], [Package 2 with a standard HP RTU]),
      (58, [Package 5], [HP RTU or boiler; economizer; DCV; energy recovery]),
      (65, [Package 12], [Rooftop PV and roof insulation]),
    ),
  ),
)
#let retrofit-names = retrofit-groups.fold((:), (names, group) => {
  for (id, name, measures) in group.at(1) {
    names.insert(str(id), name)
  }
  names
})

#figure(
  table(
    columns: (auto, auto, 1fr),
    align: (right, left, left),
    stroke: none,
    inset: (x: 4pt, y: 3pt),
    table.hline(),
    table.header([*ID*], [*Upgrade*], [*Measures*]),
    table.hline(stroke: 0.5pt),
    ..retrofit-groups
      .map(((heading, rows)) => (
        table.cell(colspan: 3, emph(heading)),
        ..rows.map(((id, name, measures)) => (str(id), name, measures)).flatten(),
        table.hline(stroke: 0.5pt),
      ))
      .flatten()
      .slice(0, -1),
    table.hline(),
  ),
  caption: [ComStock upgrades considered. IDs are ComStock 2025 upgrade numbers. HP: heat pump; RTU: rooftop unit; DCV: demand-controlled ventilation. Heat pump RTUs may use electric or original-fuel backup heat.],
  placement: none,
) <tab:upgrades>

#set page(columns: 1)

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
        apply the district-energy rule and retain $k$ nearest simulations
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
        Inverse-distance-weighted fuel-specific upgrade ratios;
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
        23 retrofits and no retrofit; decision in 2027,
        costs over 2027--2046; assess 2030 compliance
      ],
      <cmp>,
    ),
    flow_node(
      (4, 2),
      "Optimal building-level decision",
      [
        Minimum-cost option:
        a retrofit or no retrofit;
        cheapest 2030-compliant option if available
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

  placement: none,

  caption: [
    Data integration and optimization framework
    for Boston office buildings. BERDO observations, with story counts estimated from data.boston.gov building and parcel data @boston-buildings @boston-parcels, are linked to ComStock simulations through property-type-constrained nearest-neighbor matching. Estimated retrofit performance,
    BTB installation costs, AEO energy price scenarios @aeo, and Cambium grid emission rates @cambium support the 2027 decision and the comparison of costs over 2027--2046, with 2030 as the compliance milestone.
  ],
) <fig:pipeline>

== BERDO Data Exploration

#let diagnostic-counts = csv("../dbt/analysis_outputs/berdo_figure_counts.csv", row-type: dictionary).first()

These exploratory summaries precede the filtering and matching of the integrated analysis, so their populations differ from it and are reported separately.

#figure(
  image(
    "figures/berdo-emissions-standards.png",
    width: 57%,
  ),
  caption: [
    BERDO emissions-intensity standards by building use
    and compliance period, expressed in
    kg CO#sub[2]e/ft#super[2]/year @berdo-standards.
  ],
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
    Cumulative distribution of the mixed-use share, the share of non-parking floor area in uses other than office, across the #diagnostic-counts.mixed_use_offices BERDO buildings whose largest property type is Office or Financial Office. The jump at 0% is the buildings with only office and parking space.
  ],
) <fig:berdo-types>

#figure(
  image(
    "figures/berdo-intensity-cdf.png",
    width: 80%,
  ),
  caption: [
    Cumulative distribution of reported greenhouse gas emissions intensity for the #diagnostic-counts.reported_intensity_offices Office and Financial Office records that report it, compared with the 2030 BERDO office standard.
  ],
) <fig:berdo-GHGvsStandard>

The mixed-use figure covers the #diagnostic-counts.mixed_use_offices offices with a BERDO ID. The reported-intensity figure starts with all #diagnostic-counts.office_records Office and Financial Office records, including #(int(diagnostic-counts.office_records) - int(diagnostic-counts.mixed_use_offices)) without a BERDO ID, and plots the #diagnostic-counts.reported_intensity_offices with a reported intensity.

#set page(columns: 2)

== Matching Validation

Each of 618 ComStock office simulations in turn plays a BERDO building: it is hidden, its upgrade emissions are predicted from its $k$ nearest other simulations, and the prediction is compared with ComStock's simulated result across the 23 upgrades. Each configuration evaluates $618 times 23 =$ 14,214 predictions. This measures how well retrofit effects transfer between simulated buildings, not real-world accuracy.

With inverse-distance weighting and the district rule, MAE falls from 7.79 points at $k = 1$ to 6.77 at $k = 10$ and 6.65 at $k = 19$ and 20. The paired bootstrap reports production MAE minus unweighted MAE without the rule. The overall difference is −0.0959 points (95% CI −0.206 to 0.0138), which is not statistically significant. For the 73 district-energy simulations it is −0.337 points (95% CI −0.464 to −0.208), indicating lower error for that group.

// zero pads a zero to "0.000", so reference rows show a dash instead
#let or-dash(value) = if float(value) == 0 [—] else { str(value) }

#let experiment-dir = "../dbt/analysis_outputs/portfolio_matching_sensitivity/"

#let district-bootstrap = csv("../dbt/analysis_outputs/weighted_district/bootstrap.csv", row-type: dictionary)
#let district-count = district-bootstrap.find(r => r.models == "district").n
#let validation = csv("data/matching_validation.csv", row-type: dictionary).filter(
  r => r.k in ("10", "20"),
)

#figure(
  ztable(
    columns: (auto, auto, auto, auto, auto),
    format: (none, none, none, auto, auto),
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
        r.mae_pp,
        r.mae_pp_district_models,
      ))
      .flatten(),
    table.hline(),
  ),
  caption: [
    Leave-one-out mean absolute error of predicted emissions reductions, in percentage points, for all #validation.first().held_out_models simulations and the #district-count that use district energy. The project uses $k = 20$ with inverse-distance weighting and the district rule.
  ],
  placement: none,
) <tab:matching-validation>

=== Matching Features and Weights <sec:feature-matching>

We reran leave-one-out matching on the final 618 simulations and 23 retrofits (14,214 predictions per configuration) using the same fuel-ratio predictions and emissions factors as production. At $k = 20$ with the district rule, uniform pooling has 6.73 points MAE versus 6.65 for inverse distance. With inverse distance, dropping the district rule raises MAE to 6.68. The 96 combinations of $k = 1$--24, pooling method, and district rule reproduce the report's validation export to its displayed precision.

Removing stories raises mean and median error but lowers the 90th percentile. Four-term scaling divides each term by its standard deviation over eligible BERDO--ComStock pairs before the district restriction and rescales the weights to sum to four. The resulting weights for area, EUI, fuel share, and stories are 0.356, 1.09, 1.98, and 0.569. The fuel variants change the coefficient on the sum of absolute fuel-share differences from 0.5 to 0.25 or 1.5. Scaling and tripling the fuel term reduce MAE on this cohort. These comparisons use the same held-out simulations for every variant and do not validate a newly selected metric on independent data. We keep the production configuration.

#let feature-names = (
  ("production", [Production]),
  ("without_stories", [Without stories]),
  ("four_term_sd_scaled", [Scale all four terms]),
  ("fuel_half", [Half fuel term]),
  ("fuel_triple", [Triple fuel term]),
)
#let feature-results = csv(experiment-dir + "configuration_summary.csv", row-type: dictionary)

#figure(
  ztable(
    columns: (1fr, auto, auto, auto, auto),
    align: (left, right, right, right, right),
    format: (none, auto, auto, auto, (positive-sign: true)),
    inset: (x: 3pt, y: 2pt),
    stroke: none,
    table.hline(),
    table.header([*Distance*], [*MAE*], [*Median*], [*P90*], [*Δ MAE*]),
    table.hline(stroke: 0.5pt),
    ..feature-names
      .map(((key, name)) => {
        let row = feature-results.find(r => r.experiment == key)
        (name, row.mae_pp, row.median_ae_pp, row.p90_ae_pp, or-dash(row.mae_minus_production_pp))
      })
      .flatten(),
    table.hline(),
  ),
  caption: [Feature sensitivity at $k = 20$, with inverse-distance pooling and the district rule. All errors and MAE differences from production are in percentage points.],
  placement: none,
) <tab:feature-analysis>

=== HVAC Labels and Label Error

The public ComStock full baseline contains a primary HVAC-system label for each of the 618 simulations @comstock. The original HVAC comparison cannot be reproduced exactly because its mismatch rule and label-corruption procedure were not archived. In this new experiment, we add one distance unit when the held-out HVAC label differs from a candidate's label. Candidates keep their simulated labels. For each noisy run, we choose held-out labels without replacement and replace them uniformly with a different HVAC class. The four nonzero error rates use 20 replicates each with seed 5500. Each replicate still predicts all 23 upgrades for all 618 simulations.

#let hvac-results = csv(experiment-dir + "hvac_label_replicates.csv", row-type: dictionary)
#let hvac-rates = hvac-results.map(r => float(r.target_error_rate)).dedup().sorted()

#figure(
  ztable(
    columns: (1fr, auto, auto, auto, auto),
    align: (left, right, right, right, right),
    // P90 spans 9.26 to 14.2, so one decimal keeps the column even
    format: (none, auto, auto, (round: (mode: "places", precision: 1)), (positive-sign: true)),
    inset: (x: 3pt, y: 2pt),
    stroke: none,
    table.hline(),
    table.header([*Wrong labels*], [*MAE*], [*Median*], [*P90*], [*Δ MAE*]),
    table.hline(stroke: 0.5pt),
    ..hvac-rates
      .map(rate => {
        let runs = hvac-results.filter(r => float(r.target_error_rate) == rate)
        let mean(field) = runs.fold(0.0, (sum, row) => sum + float(row.at(field))) / runs.len()
        (
          str(int(calc.round(100 * rate))) + "%",
          str(mean("mae_pp")),
          str(mean("median_ae_pp")),
          str(mean("p90_ae_pp")),
          or-dash(mean("mae_minus_production_pp")),
        )
      })
      .flatten(),
    table.hline(),
  ),
  caption: [Experimental HVAC matching at $k = 20$ with inverse-distance pooling and the district rule. Units are percentage points. At nonzero noise rates, entries are averages of the per-replicate statistics. Differences use the production result without HVAC labels.],
  placement: none,
) <tab:hvac-analysis>

Accurate simulated HVAC labels lower MAE from 6.65 to 3.74 points in this test. The gain shrinks as labels become less accurate but remains at 50% corruption under this procedure. The result depends on the mismatch penalty and the way labels are corrupted. BERDO and assessor records lack commercial HVAC labels, and this experiment does not establish how a real label source would perform. Earlier tests of year built, wall construction, window type, and operating hours lack a recoverable protocol and were not rerun.

#block(breakable: false)[
  === Prediction Errors by Retrofit Option

  #let upgrade-errors = csv(experiment-dir + "production_by_upgrade.csv", row-type: dictionary)

  #figure(
    ztable(
      columns: (auto, 1fr, auto, auto),
      align: (right, left, right, right),
      format: (none, none, (round: (mode: "places", precision: 2)), (round: (mode: "places", precision: 2))),
      inset: (x: 3pt, y: 2pt),
      stroke: none,
      table.hline(),
      table.header([*ID*], [*Upgrade*], [*Mean cut (%)*], [*MAE (pp)*]),
      table.hline(stroke: 0.5pt),
      ..upgrade-errors
        .map(row => (
          row.upgrade_id,
          retrofit-names.at(row.upgrade_id),
          row.mean_simulated_reduction_pct,
          row.mae_pp,
        ))
        .flatten(),
      table.hline(),
    ),
    caption: [Final production leave-one-out errors by ComStock upgrade. Each upgrade is evaluated on #upgrade-errors.first().predictions held-out ComStock simulations. Mean cut is the average simulated emissions reduction; MAE is expressed in percentage points of baseline emissions.],
    placement: none,
  ) <tab:per-upgrade-validation>
]

Heat pump rooftop unit (RTU) options miss by 8.14--10.48 points against simulated cuts of 6.68--8.55%. The electric-backup boiler misses by 4.05 points on a 7.02% cut. VRF and geothermal have the largest errors. Individual envelope, lighting, and rooftop PV measures miss by 1.10--2.68 points, ventilation measures by 0.11--4.77, and combined Packages 2--5 by 8.64--10.57 points.

== Story Estimates

Stories come from the city's roof outlines, whose heights are recorded for 2010 @boston-buildings, placed on the 2025 parcels @boston-parcels. Of the 297 offices, 218 use floor area over footprint, confirmed by roof height; 45 use roof height, because the two disagree or the parcel holds more than one BERDO building; 3 use floor area over footprint with no height to check it; and 31 have no estimate.

The outlines have been updated since 2010, but the newer footprints carry no height. These skew new. By the FY2026 assessor's year built @boston-assessment, 41 of the 110 BERDO buildings whose footprint has no measured height and whose year is known (37%) were built in 2010 or later, against 7% of buildings with a measured height. Their floor-area estimate is used unchecked, which fails when the parcel holds only a fragment of a building. BERDO 104376, built in 1914, has 110,005 sq ft over a 175 sq ft fragment, or 630 stories. The model discards unchecked estimates above 60 stories, so 104376 joins the offices without an estimate.

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

If the matched simulations have no baseline consumption for a fuel, its ratio is one. For no retrofit, the model starts from BERDO's reported total and adjusts only its electricity portion.

== 20-Year Global Cost

Each option is costed in 2025 dollars over $N = 20$ years from 2027 ($t = 1$ is 2027) at discount rate $rho$, 0.07 for the owner and 0.02 for society. A component $m$ with installed cost $K_m$ and BTB lifetime $L_m$ is installed at the start and replaced every $L_m$ years, and its last installation is credited its straight-line remaining value at the horizon:

$
  V_m = K_m (sum_(j=0)^(J_m) (1 + rho)^(-j L_m) - lambda_m (1 + rho)^(-N))
$

where $J_m$ is the last $j$ with $j L_m < N$ and $lambda_m = ((J_m + 1) L_m - N) \/ L_m$ is the share of the last installation's life left at the horizon. Existing heating and cooling equipment $e in H_b$ is valued the same way, with each replacement delayed by its remaining life. The global cost is

$
  C_(b,p) = & sum_(m in p) V_m + bb(1)_p sum_(e in H_b) V_e \
            & + sum_(t=1)^N (E_(b,p,t) + P_(b,p,t)) / (1 + rho)^t
$

where $bb(1)_p$ is one for options that keep the existing equipment. The energy bill is $E_(b,p,t) = sum_f Q_(b,f) r_(b,p,f) c_f pi_(f,t)$, with $Q_(b,f)$ the building's reported use of fuel $f$, $c_f$ its 2025 price, and $pi_(f,t)$ the AEO price index (2025 = 1). The owner's emissions cost is the ACP, $P_(b,p,t) = 0.234 max(0, G_(b,p,t) - S_t A_b)$, where $S_t$ is the standard in force in year $t$ and $A_b$ is floor area. Society's is $P_(b,p,t) approx 0.281 tilde(G)_(b,p,t)$, using the EPA's \$230 per metric ton in 2020 dollars converted to 2025 dollars, where $tilde(G)$ replaces BERDO's electricity factor index $e_y$ with Cambium's grid emission rate index. Both rates are in dollars per kilogram. Operation and maintenance costs are left at zero, since BTB gives none.

== Break-Even ACP

From the owner's view, an option's 20-year cost is linear in the ACP rate $a$: $C_(b,p)(a) = F_(b,p) + a T_(b,p)$, where $T_(b,p)$ is the present value of its tons over the limit and $F_(b,p)$ is everything else. A compliant option beats another wherever its line is lower. An office's break-even rate is the lowest $a$ at which some compliant option beats every other option, compliant or not (@fig:breakeven).

== Farnsworth Street Cost and Emissions Comparison

The Farnsworth Street boiler's global cost is \$2.78 million for the owner and \$4.45 million for society. It exceeds its applicable limit in two of the 20 years. @tab:farnsworth-results compares its installation cost and emissions with the other options.

#let case-results = csv("../dbt/analysis_outputs/case_study_106476.csv", row-type: dictionary).filter(
  r => r.perspective == "financial",
)
#let case-base = float(case-results.find(r => r.upgrade_id == "0").projected_intensity_kgco2e_sqft)
#let case-options = (
  ("0", [No retrofit]),
  ("15", [Heat pump boiler]),
  ("21", [Air-handler recovery]),
  ("55", [Package 2]),
  ("56", [Package 3]),
  ("57", [Package 4]),
  ("58", [Package 5]),
  ("65", [Package 12]),
)

#figure(
  ztable(
    columns: (1fr, auto, auto, auto),
    align: (left, right, right, right),
    format: (none, (round: (mode: none)), (round: (mode: none)), (round: (mode: "places", precision: 1))),
    inset: (x: 3pt, y: 3pt),
    stroke: none,
    table.hline(),
    table.header([*Option*], [*Install.*], [*Global*], [*2030 cut (%)*]),
    table.hline(stroke: 0.5pt),
    ..case-options
      .map(((id, name)) => {
        let row = case-results.find(r => r.upgrade_id == id)
        let thousands(value) = str(int(calc.round(float(value) / 1000)))
        let cut = 100 * (1 - float(row.projected_intensity_kgco2e_sqft) / case-base)
        ([#name (#id)], thousands(row.installed_cost_mid_usd), thousands(row.global_cost_mid_usd), or-dash(cut))
      })
      .flatten(),
    table.hline(),
  ),
  caption: [Representative options for BERDO 106476. Gross installation and owner global costs are in thousands of 2025 dollars. Global cost covers 2027--2046 at mid installation costs and baseline prices with projected grid factors. The modeled 2030 emissions cut is relative to the no-retrofit intensity of #num(str(case-base)) kg CO#sub[2]e/ft#super[2]/year. Source: dbt global-cost and upgrade-compliance outputs.],
) <tab:farnsworth-results>

== Neighbor Sensitivity

For example, the owner's cheapest compliant option for 105302 (2--16 Tremont Street) is roof insulation at $k = 1$--2, then settles on the variable-speed heat pump RTU with energy recovery from $k = 7$ on. @fig:k-sensitivity shows how often recommendations change across the cohort.

We independently re-ranked the final 20-year cost rows at every $k$ from 1 through 20. All 23 retrofit IDs occur across the cohort at each $k$, plus the no-retrofit baseline. Individual offices retain only applicable options under the existing rules. The audit uses the 2027--2046 horizon, the 2030 compliance milestone, projected grid factors, baseline prices, and mid installation costs, with owner and societal discount rates of 7% and 2%. The recomputed counts match the existing sensitivity figure and its $k = 20$ reference. At Tremont Street, standalone RTUs are the cheapest compliant options at $k = 3$, $4$, and $6$. The energy-recovery RTU remains cheapest from $k = 7$ through 20. At Farnsworth Street, the standalone electric-backup boiler remains cheapest at the reference setting from both perspectives.

== Additional Results <sec:additional-results>

How close are the matches? For the median office, its 20 matched simulations differ on average by about 32% in floor area, 23% in EUI, and 28% in stories, and 17% of their energy is in a different fuel. For the worst-matched tenth, floor area and EUI differ by 66% and 74%.

Matching against all-office pooling improves MAE by 0.90 points (95% CI 0.58--1.22) and lowers error for 68.9% of the held-out simulations. Under the frozen grid factor, the owner's compliant count remains 42 of 99 when switching to AEO baseline prices. Under projected conditions, the societal count ranges from 44 to 47 across alternative price cases. Of the 71 offices with a compliant option, 21 have a break-even ACP above \$1,000 per metric ton, including six above \$10,000.

At $k = 20$, the median absolute error is 2.82 points and the 90th percentile is 19.9. Heat pump options are chosen for 33 buildings from each perspective.

The cheapest choice is unchanged across low, mid, and high BTB installation costs for 33 offices from the owner's view and 61 from society's. At Farnsworth Street, Packages 2 and 4 tie for second. Air-handler energy recovery is the owner's cheapest option that misses the 2030 limit and costs about \$162,000 more than the boiler.

Under projected conditions, the cheapest option stays cheapest in at least 90% of Monte Carlo draws for 25 offices from the owner's view and 32 from society's. It stays cheapest in fewer than half for 12 and 7, respectively. Under frozen conditions, the corresponding counts are 22 and 32 at or above 90%, and 11 and 5 below half. Expected regret is the extra cost of keeping the original recommendation compared with choosing the cheapest option in each draw. Summed across offices, expected regret is \$0.92 million for the owner and \$3.40 million for society under projected conditions, and \$1.33 million and \$4.04 million under frozen conditions.

With grid factors and prices frozen at 2025 levels, mean recommendation stability is 71.9% for the owner and 79.9% for society. Of the 35 owner recommendations that meet the 2030 limit in the central projection, 26 meet it in at least 90% of draws. Only one of those 35 meets the 2046 limit in at least 90% of draws.

At $k = 1$, $10$, and $19$, the owner's cheapest option overall changed for 52, 17, and 1 of the 81 offices, and society's for 38, 13, and 2. The owner next selects the variable-speed heat pump RTU with energy recovery (16 offices, 5 compliant) and the electric-backup boiler (12 offices, 11 compliant). Six owner Package 12 picks are compliant. The heat pump boiler is the second most common societal pick (21 offices).
