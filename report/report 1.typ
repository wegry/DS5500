
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
  abstract: [
    #todo[Update to narrow focus to offices]
    Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO)
    requires large buildings to cut their emissions on a fixed schedule, down
    to net zero by 2050. Owners have more candidate retrofit projects than
    capital, and the usual way to choose between them is to rank projects by
    cost per ton avoided. That ignores both interactions between projects and
    the timing of each investment. We propose a decision-support tool that
    picks the portfolio and the schedule together with a multi-period
    mixed-integer program. It is built on real BERDO disclosures for about
    5,600 Boston buildings, plus public upgrade, price, and grid emissions
    data, and compared directly against the ranked approach.
  ],
  index-terms: (
    "Decarbonization",
    "BERDO",
    "Capital budgeting",
    "Building energy",
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

Under Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO), residential buildings with 15 or more units and nonresidential
buildings of 20,000 sq ft or more have to report their energy use
every year and meet emissions limits that step down over time, reaching net
zero by 2050 (@fig:berdo-limits) @berdo. The owner of one of these buildings, say an office, has a list of candidate
projects: heat pumps, envelope upgrades, LED retrofits, rooftop solar,
switching off fuel oil, etc. If a retrofit is not economical, the owner can instead pay a non-compliance fee. Either way, the owner does not have the capital to do all of the updates at once,
so somebody has to pick an order. The standard tool for that is a marginal
abatement cost curve (MACC), which ranks projects by dollars per ton of
CO#sub[2] avoided and funds them from the cheapest on down.

That ranking treats every project as independent and every year as the same.
Neither is true. A heat pump in a building that was just insulated saves less
than the two estimates added together. And under BERDO, _when_ a building gets
under its limit matters as much as _whether_ it does, since each building has
its own first compliance year and the limits keep tightening after that.

Our goal is to develop a decision-support tool that helps university and college building owners in Boston determine which decarbonization projects to implement and when (@fig:pipeline). MACC will serve as our baseline. Rather than simply ranking projects individually, the tool will produce a multi-year investment roadmap that considers limited annual capital, financial returns, emissions reduction, and building-specific BERDO emissions requirements.

= Methods

== Data

The project will rely primarily on public data, so it does not depend on
obtaining proprietary data. *BERDO disclosures* @berdo provide the building-level
starting point, including property type, floor area, energy use, emissions by
fuel, and projected first compliance year. We will clean and screen these data
for missing values, outliers, and campus-level reporting before selecting a
portfolio of buildings for analysis. *ComStock* @comstock will then be matched
to the selected buildings by characteristics such as property type and climate
to estimate the energy impacts of candidate retrofit measures and packages. ComStock may be tricky to reconcile with Boston's older and denser building stock.
Technology cost and performance assumptions will be drawn from the *Annual
Technology Baseline* @atb, energy-price projections from the *EIA Annual Energy
Outlook* @aeo, and grid-emissions factors from *Cambium* @cambium and *EPA
eGRID* @egrid. Anonymized project data from a sustainability consulting firm,
if available, will be used only for real-world validation of modeled costs and
savings rather than as a requirement for the project.

== Methods #todo[Change name]

Using these inputs, we will construct a set of candidate decarbonization
projects for the selected building portfolio. Each project will include an
estimated implementation cost, annual energy and financial savings, emissions
reduction, and possible implementation year. We will formulate the capital
planning problem as a multi-period optimization model in which each candidate
project can be implemented in a particular year or not selected. The model
will seek to maximize the financial value of the investment portfolio while
accounting for annual capital limits and building-specific BERDO emissions
requirements. BERDO alternative compliance payments can also be represented
so that the model can compare the cost of exceeding an emissions limit with
the cost of investing in additional retrofits. We plan to implement the model
in Pyomo @pyomo using the open-source HiGHS solver @highs. Scenario and
sensitivity analysis will be used to test how the roadmap changes under
alternative assumptions about future energy prices, grid emissions, and
project performance; more complex stochastic formulations will be treated as
an extension if time permits.

#let stage(body) = box(
  stroke: 0.5pt,
  radius: 2pt,
  inset: (x: 4pt, y: 5pt),
  width: 100%,
  {
    set par(justify: false)
    set text(8pt, hyphenate: false)
    align(center, body)
  },
)
#let arrow = align(center + horizon)[→]

#figure(
  grid(
    columns: (1fr, 12pt, 1fr, 12pt, 1fr),
    align: horizon,
    stage[*BERDO buildings*\ + candidate\ upgrades],
    arrow,
    stage[*Optimization model*\ multi-period capital planning],
    arrow,
    stage[*Investment roadmap*\ project, building, and start year],
  ),
  caption: [Project pipeline.],
) <fig:pipeline>

== Evaluation

To determine whether the added complexity of optimization provides practical
value, we will compare the resulting roadmap against a MACC baseline applied to the same buildings and candidate projects.
The two approaches will be evaluated on financial performance, cumulative
emissions reductions, BERDO compliance, and capital deployment over the
planning horizon. The final output will be a year-by-year investment roadmap
showing a building owner which projects to implement, on which buildings, and
when. A meaningful improvement over the MACC baseline would support the use of
optimization as a capital-planning tool; if the simpler ranking performs
similarly, that is also a useful result for practitioners deciding whether the
additional modeling effort is justified.

= Results

Preliminary exploration of the 2026 BERDO dataset supports the feasibility of our proposal. The dataset contains 5,592 building records representing 58 distinct building types, along with detailed information on property size, ownership, BERDO compliance timing, and emissions by energy source. Ownership information is available for nearly all buildings, with only 18 records lacking an owner and 3,178 individual property owners represented. BERDO also identifies 37 building portfolios, with reported total gross floor areas ranging from approximately 80,000 to 17.6 million square feet, excluding the Boston Housing Authority portfolio at approximately 146 million square feet. "College / University" types (field `Largest Property Type`) have seven distinct universities.

Initial exploration also identified data-quality issues that will inform preprocessing and portfolio selection. Some source-specific emissions fields are missing even when they may be applicable, and repeated ownership information is not always populated consistently. The BERDO portfolio groupings themselves will also require validation before use, as preliminary inspection revealed some unexpected differences in reported portfolio size. We will evaluate missingness and verify the portfolio definitions before selecting buildings or portfolios with sufficiently complete and consistent data. If needed, we will contact the City of Boston BERDO team to clarify how portfolio groupings are to confirm whether the published groupings are appropriate for our analysis.


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

#figure(
  image("figures/berdo-emissions-standards.png", width: 65%),
  caption: [BERDO emissions standards (kgCO#sub[2]e/ft#super[2]/year) by
    building use for each five-year compliance period, reaching zero in 2050
    @berdo-standards.],
) <fig:berdo-limits>

#todo[supplementary figures, tables, and technical details.]
