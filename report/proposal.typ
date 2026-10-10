// Optimizing Corporate Decarbonization Investments
// Expanded from Konstantinos Theodoropoulos' solo pitch (DS5500, Fall 2026).
// Build: typst compile proposal.typ

#import "@preview/charged-ieee:0.1.4": ieee

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
        #link("https://github.com/wegry/DS5500")[github.com/wegry/DS5500]
      ],
    ),
  ),
  // abstract: [
  //   Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO)
  //   requires large buildings to cut their emissions on a fixed schedule, down
  //   to net zero by 2050. Owners have more candidate retrofit projects than
  //   capital, and the usual way to choose between them is to rank projects by
  //   cost per ton avoided. That ignores both interactions between projects and
  //   the timing of each investment. We propose a decision-support tool that
  //   picks the portfolio and the schedule together with a multi-period
  //   mixed-integer program. It is built on real BERDO disclosures for about
  //   5,600 Boston buildings, plus public upgrade, price, and grid emissions
  //   data, and compared directly against the ranked approach.
  // ],
  index-terms: (
    "Decarbonization",
    "BERDO",
    "Mixed-integer programming",
    "Capital budgeting",
    "Building energy",
  ),
  bibliography: bibliography("refs.bib"),
)

#set document(author: (
  "Konstantinos Theodoropoulos",
  "Zachary Wegrzyniak",
  "Kateryna Lysytsyna",
))

// ---- 3: goal / outcome ----------------------------------------------------

= Summary

Under Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO), residential buildings with 15 or more units and nonresidential
buildings of 20,000 sq ft or more in Boston have to report their energy use
every year and meet emissions limits that step down over time, reaching net
zero by 2050 @berdo. An owner with several of these buildings, such as a
university, have a list of candidate
projects: heat pumps, envelope upgrades, LED retrofits, rooftop solar,
switching off fuel oil, etc. They don't have the capital to do all of them at once,
so somebody has to pick an order. The standard tool for that is a marginal
abatement cost curve (MACC), which ranks projects by dollars per ton of
CO#sub[2] avoided and funds them from the cheapest on down.

That ranking treats every project as independent and every year as the same.
Neither is true. A heat pump in a building that was just insulated saves less
than the two estimates added together. And under BERDO, _when_ a building gets
under its limit matters as much as _whether_ it does, since each building has
its own first compliance year and the limits keep tightening after that.

Our goal is to develop a decision-support tool that helps university and college building owners in Boston determine which decarbonization projects to implement and when (@fig:pipeline). MACC will serve as our baseline. Rather than simply ranking projects individually, the tool will produce a multi-year investment roadmap that considers limited annual capital, financial returns, emissions reduction, and building-specific BERDO emissions requirements.

= Proposed Plan

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

== Methods

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

= Preliminary Results

Preliminary exploration of the 2026 BERDO dataset supports the feasibility of our proposal. The dataset contains 5,592 building records representing 58 distinct building types, along with detailed information on property size, ownership, BERDO compliance timing, and emissions by energy source. Ownership information is available for nearly all buildings, with only 18 records lacking an owner and 3,178 individual property owners represented. BERDO also identifies 37 building portfolios, with reported total gross floor areas ranging from approximately 80,000 to 17.6 million square feet, excluding the Boston Housing Authority portfolio at approximately 146 million square feet. "College / University" types (field `Largest Property Type`) have seven distinct universities.

Initial exploration also identified data-quality issues that will inform preprocessing and portfolio selection. Some source-specific emissions fields are missing even when they may be applicable, and repeated ownership information is not always populated consistently. The BERDO portfolio groupings themselves will also require validation before use, as preliminary inspection revealed some unexpected differences in reported portfolio size. We will evaluate missingness and verify the portfolio definitions before selecting buildings or portfolios with sufficiently complete and consistent data. If needed, we will contact the City of Boston BERDO team to clarify how portfolio groupings are to confirm whether the published groupings are appropriate for our analysis.

= Project Milestones

// Add dated milestones and measurable deliverables here once the course
// schedule and preliminary BERDO analysis are finalized.
Our plan is to complete the project over ~7 weeks. Once agreed on the input format, we are going to run data preparation, optimization, and baseline development in parallel. We will first test the data preparation and both planning methods on a few buildings before applying them to a larger sample.

#[
  #set par(justify: false)

  #table(
    columns: (auto, 1fr),
    inset: 5pt,
    stroke: 0.5pt,
    align: left + top,

    table.header([*Timeline*], [*Milestone and deliverable*]),

    [10/07 - 10/11],
    [*Explore data and define scope*: check BERDO and ComStock coverage, select initial buildings and upgrades, agree on shared columns.],

    [10/12 - 10/18],
    [*Build a small working example*: match a few buildings and prepare initial upgrade estimates; connect this sample to early versions of the optimizer and MACC baseline.],

    [10/19 - 11/01],
    [*Complete inputs and models*: expand the sample, add cost, price, and emission inputs; run the optimization model and MACC ranking using the same data and yearly budgets to compare which upgrades each selects and when.],

    [11/02 - 11/08],
    [*Evaluate results*: compare financial value, emissions, and spending; check how the results change if upgrades cost more, energy prices change, or energy savings are lower than expected.],

    [11/09 - 11/15],
    [*Prepare drafts*: complete the main figures, document methods and limitations; draft the report and final presentation.],

    [11/16 - 11/22],
    [*Finalize and submit*: resolve remaining issues, check reproducibility, finalize the report and final presentation.],
  )
]


// ---- 5: risks / challenges ------------------------------------------------

= Risks and Challenges

== Self-Reported Data
BERDO numbers are reported by building owners. Some buildings are missing
years, some report whole campuses together, and some values will just be
wrong. We'll need to screen for outliers and decide how to handle campuses
before any building goes into the model.

== Matching Buildings to Upgrades
ComStock's buildings are representative, not real. A Boston office building
from 1920 on district steam may not look much like any ComStock office, so
the savings we attach to it could be off. Validating that match, against
buildings whose reported energy use changed after a known retrofit, is where
the consulting data would help most.

== Uncertainty in the Future
Energy prices, realized savings, and the grid mix in 2035 are all forecasts. A
deterministic optimizer will happily overfit to whichever one it's handed. We
plan to solve across the AEO and Cambium scenarios and report which decisions
hold up in all of them, rather than the best plan for one future.
Scenario-based stochastic programming is the likely formulation, but it grows
fast with the number of scenarios.

== Projects Interact
Savings aren't additive, and modeling every combination of projects blows up
the problem size. ComStock's packages cover some combinations. The rest need
an approximation, and that approximation is the most likely place for the
model to be quietly wrong.

== Which Emission Factor
BERDO scores electricity with its own emission factors, which aren't the same
as the hourly ISO New England reported intensity, or the marginal plant
that actually ramps up to serve new load from a heat pump. A plan can be compliant on paper and still do less for the actual grid.
We'll report both instead of picking whichever one flatters the result.
