
// Optimizing Corporate Decarbonization Investments
// Expanded from Konstantinos Theodoropoulos' solo pitch (DS5500, Fall 2026).
// Build: typst compile proposal.typ

#import "@preview/charged-ieee:0.1.4": ieee

// Red placeholder so unfinished rubric sections stand out in the PDF.
#let todo(body) = text(fill: red)[*TODO:* #body]

// ---- 1 & 2: name and title ------------------------------------------------

#show: ieee.with(
  title: [Optimizing Corporate Decarbonization Investments: Which Projects to Fund, and in What Year],
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
  abstract: [Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) requires large buildings to meet increasingly strict greenhouse gas emissions limits, with a major compliance milestone in 2030. This project focuses on Boston office buildings and aims to identify the most cost-effective retrofit decisions for the 2030 compliance period. We combine BERDO building disclosures, NLR ComStock energy and emissions estimates, and Building Technologies Benchmark (BTB) installation cost data to evaluate candidate retrofit packages. For each building, we estimate emissions reductions and associated installation costs, then compare the available retrofit options against the financial consequences of noncompliance. Our optimization framework selects one of five outcomes: four potential retrofit packages or no upgrade when accepting Alternative Compliance Payments (ACP). The resulting framework supports building-level investment decisions by balancing emissions reduction requirements against financial costs.
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

Our goal is to develop a decision-support tool that helps building owners in Boston determine which decarbonization projects to implement and when (@fig:pipeline). MACC will serve as our baseline. Rather than simply ranking projects individually, the tool will produce a multi-year investment roadmap that considers limited annual capital, financial returns, emissions reduction, and building-specific BERDO emissions requirements.

= Methods

== Data

This project uses three publicly available data sources: Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) disclosures, National Lab of the Rockies (NLR) ComStock, and the NLR 2024 Buildings Technology Baseline (BTB).

*BERDO* provides building-level information, including property type, gross floor area, energy consumption by fuel, and greenhouse gas emissions @berdo. The analysis focuses on Boston office buildings because these buildings have a relatively high emissions reporting rate. Records are prepared using dbt models that standardize property types for storage in duckdb, convert the fuels BERDO reports in kBtu (natural gas, district energy, and oil/propane) to kWh to match electricity, aggregate related fuel categories, and identify missing or inconsistent values. BERDO provides:
- the observed building characteristics
- baseline emissions for the analysis
- a way to derive ACPs and identify noncompliant buildings

*ComStock* provides simulated commercial building characteristics, baseline energy consumption, and estimates of the impacts of energy-efficiency upgrades @comstock. Our data flow uses Suffolk County ComStock simulations, including baseline and upgrade scenarios. Energy measurements are standardized, and weighted energy consumption values are converted to per-building quantities using ComStock simulation weights.

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

*Retrofit performance estimation.* ComStock baseline and upgrade scenarios are linked using their synthetic building identifiers. For each BERDO building and upgrade, the ratio of total upgraded to baseline energy consumption is calculated separately for electricity, natural gas, oil/propane, district heating, and district cooling across the matched simulations.

The fuel-specific ratios are applied to the corresponding BERDO building's observed energy consumption and greenhouse gas emissions. This approach preserves the building's reported emissions baseline and fuel-specific emissions factors while transferring the modeled effects of ComStock upgrades.

If the matched simulations have no baseline consumption for a particular fuel, its ratio is set to one, leaving that fuel unchanged. Upgrade applicability is also summarized across the matched simulations. Because BERDO does not contain a complete inventory of installed equipment, the estimated impacts represent modeled retrofit opportunities rather than verified building-specific improvements.

*Installation cost estimation.* Each of the four selected ComStock retrofit packages will be mapped to its corresponding technologies in BTB @btb. Installation costs will be calculated using the corresponding technology-level cost parameters and relevant building characteristics, such as gross floor area or equipment capacity. Units will be standardized before cost estimation, and missing cost values will be documented and addressed using explicit assumptions or sensitivity ranges where supported.

The integration workflow is summarized in @fig:pipeline.


// Methodology figure

#let sci_box(heading, detail) = rect(
  width: 100%,
  radius: 0pt,
  stroke: 0.6pt + black,
  fill: white,
  inset: (x: 7pt, y: 6pt),
  align(center, [
    #text(size: 8pt, weight: "bold")[#heading]
    #linebreak()
    #text(size: 7pt)[#detail]
  ]),
)

#let sci_arrow = align(center, text(size: 10pt)[↓])

#figure(
  stack(
    dir: ttb,
    spacing: 4pt,

    // Input datasets
    grid(
      columns: (1fr, 1fr, 1fr),
      gutter: 8pt,

      sci_box(
        "BERDO",
        [Observed office buildings: area, EUI, fuel use, GHG],
      ),

      sci_box(
        "ComStock",
        [Synthetic baselines and upgrade simulations],
      ),

      sci_box(
        "BTB",
        [Technology-level installation cost parameters],
      ),
    ),

    // Data processing
    grid(
      columns: (2fr, 1fr),
      gutter: 8pt,
      sci_arrow, sci_arrow,
    ),

    grid(
      columns: (2fr, 1fr),
      gutter: 8pt,

      sci_box(
        "BERDO--ComStock matching",
        [
          Property-type crosswalk;
          rank by custom distance $d(b,c)$;
          retain $k$ nearest simulations
        ],
      ),

      sci_box(
        "Technology cost mapping",
        [
          Map package components
          to BTB cost functions
        ],
      ),
    ),

    grid(
      columns: (2fr, 1fr),
      gutter: 8pt,
      sci_arrow, sci_arrow,
    ),

    // Intermediate outputs
    grid(
      columns: (2fr, 1fr),
      gutter: 8pt,

      sci_box(
        "Retrofit emissions estimation",
        [
          Pooled fuel-specific upgrade ratios;
          projected emissions for each
          BERDO building and package
        ],
      ),

      sci_box(
        "Installation cost estimation",
        [
          Estimated capital cost
          per building and package
        ],
      ),
    ),

    sci_arrow,

    // Optimization
    sci_box(
      "BERDO 2030 cost comparison",
      [
        Four retrofit packages and no-retrofit
        alternative; installation costs plus
        residual Alternative Compliance Payments
      ],
    ),

    sci_arrow,

    sci_box(
      "Optimal building-level decision",
      [
        Minimum-cost option:
        retrofit package 1--4 or ACP-only
      ],
    ),
  ),

  placement: top,
  scope: "parent",

  caption: [
    Data integration and optimization framework
    for Boston office buildings. BERDO observations are linked to ComStock simulations through property-type-constrained nearest-neighbor matching. Estimated retrofit performance and
    BTB installation costs support the selection of cost-effective 2030 compliance options.
    #todo[Is there a way to get arrows for Installation cost estimation being merged to match BERDO and Comstock being merged above?]
  ],
) <fig:pipeline>


*2030 compliance assessment.* BERDO establishes an office building emissions standard of 3.2 kg $"CO"_2"e"$ per square foot per year for the 2030-2034 compliance period @berdo-standards. For each building and retrofit scenario, estimated emissions are divided by gross floor area and compared with the applicable standard.

The existing data flow's compliance model calculates projected emissions intensity, whether the building meets the standard, and the amount of emissions exceeding the limit. It also includes an no-upgrade scenario representing no retrofit.

For emissions exceeding the limit, BERDO permits ACPs. The current payment rate is \$234 per metric ton of CO2e above the emissions limit @berdo-acp. Annual ACP obligations are estimated from the remaining excess emissions after each retrofit scenario.


*Cost optimization.* The proposed framework identifies the most cost-effective retrofit decision for meeting Boston office buildings' 2030 BERDO obligations. Four candidate retrofit packages are compared with a no-retrofit alternative using a five-year financial evaluation period (2030--2034).

For each alternative, total modeled cost consists of the estimated installation cost and cumulative Alternative Compliance Payments (ACPs) associated with any remaining excess emissions. The baseline analysis assumes constant annual emissions and ACP rates throughout the evaluation period. The model ranks the alternatives with the most impactful realistic upgrade for each building.


== Evaluation

The proposed methodology will be evaluated by comparing installation costs, projected greenhouse gas emissions reductions, and BERDO compliance outcomes across the four retrofit packages. The no-retrofit alternative will serve as the financial baseline, allowing us to estimate whether implementing an upgrade reduces total modeled costs relative to relying on ACPs.

We will examine the distribution of recommended decisions across Boston office buildings, including the proportion of buildings for which each retrofit package is preferred and those for which ACPs are more economical.

The quality of BERDO--ComStock matching will be evaluated using matching distances and differences in building characteristics. Possible sensitivity analysis will assess how the number of nearest neighbors, estimated retrofit performance, installation costs, and incomplete upgrade applicability information affect the recommendations.

The analysis has several limitations. ComStock represents simulated rather than observed building systems, while BERDO does not provide a complete inventory of existing equipment. Additionally, the current emissions projections hold reported fuel-specific emissions factors constant, without explicitly modeling future changes in electricity emissions intensity. Installation costs are estimated from technology-level benchmarks rather than building-specific engineering assessments.

The resulting recommendations will therefore be interpreted as preliminary investment estimates for the 2030--2034 period rather than verified retrofit plans.


= Preliminary Results

== Data Exploration and Feasibility

Preliminary exploration focused on assessing the availability and suitability of the BERDO, ComStock, and BTB datasets for the proposed analysis.

The BERDO disclosure provides building-level information on property type, gross floor area, energy consumption, greenhouse gas emissions, and more @berdo. The dataset published for 2026 contains 5,591 building records, a substantial amount for analysis. However, because BERDO relies on self-reported building information, missing and inconsistent values limit the number of usable records. An examination of data completeness across building categories revealed considerable variation, with office buildings exhibiting higher completeness than other building types (@fig:berdo-heatmap).

Of the 5,591 records, 410 were identified as having office space as their primary or sole use. This subset provided a relatively large population of records with complete entries to support the BERDO-ComStock matching step.

To measure the potential need for decarbonization investments, reported greenhouse gas (GHG) emissions intensities were compared against the 2030-2034 BERDO standard for offices of 3.2 kg of $"CO"_2"e"$ per square foot per year @berdo-standards. 290 of the 410 office buildings reported GHG intensity values, of which 96 or 33.1% exceeded the 2030 standard (@fig:berdo-GHGvsStandard). This number suggests that a substantial portion of offices might face compliance challenges, highlighting the need for the evaluation of retrofit upgrades and their cost.

ComStock provides baseline simulations and retrofit scenarios with information on building characteristics, fuel consumption, and upgrade applicability @comstock. These variables support the proposed building-matching procedure and estimation of retrofit performance.

Exploration of the BTB commercial dataset identified installation cost information for technologies corresponding to components of the candidate ComStock retrofit packages @btb. However, the completeness of package-level cost estimates remains under investigation.

== Current Limitations

Although the data integration and emissions projection models have been developed, their building-level outputs have not yet been fully evaluated. Matching quality, emissions reductions under the four selected packages, and the resulting 2030 compliance outcomes remain to be assessed.

Installation cost integration and the final cost optimization are also incomplete. Consequently, no optimal retrofit recommendations are reported at this stage.


// ---- 9: discussion --------------------------------------------------------

= Discussion

#todo[What did we learn from the results? How can a building owner apply
  them, and what decisions do they support? Were the project goals met? What
  would we do differently, or do next to improve the outcome?]

// ---- 10: statement of contributions ---------------------------------------

= Statement of Contributions

- *Konstantinos Theodoropoulos:* #todo[contributions]
- *Zachary Wegrzyniak:* #todo[contributions]
- *Kateryna Lysytsyna:* #todo[contributions]

// ---- 11: references -------------------------------------------------------

#bibliography("refs.yml")

// ---- 12: appendix ---------------------------------------------------------

// Changing the page's columns starts a new page, and one column lets the
// appendix figures sit in order without floating.
#set page(columns: 1)

= Appendix

Source code is available at
#link("https://github.com/wegry/DS5500")[github.com/wegry/DS5500].

#show figure.caption: set align(center)

#figure(
  image("figures/berdo-emissions-standards.png", width: 65%),
  caption: [BERDO emissions standards (kgCO#sub[2]e/ft#super[2]/year) by
    building use for each five-year compliance period, reaching zero in 2050
    @berdo-standards.],
) <fig:berdo-limits>

#figure(
  image("figures/berdo-completeness.png", width: 75%),
  caption: [Data completeness heatmap by building category],
) <fig:berdo-heatmap>

#figure(
  image("figures/berdo-intensity-vs-benchmark.png", width: 75%),
  caption: [Reported office-building GHG intensities vs. the 2030 BERDO standard],
) <fig:berdo-GHGvsStandard>

#todo[supplementary figures, tables, and technical details.]
