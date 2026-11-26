// DS5500 Presentation 3: ACP vs. retrofit for Boston offices under BERDO.
// Follows the team's PowerPoint draft (Team7_BERDO_Integrated_Data_and_Optimizer.pptx),
// rebuilt here so figures and numbers come straight from the pipeline outputs.
//
// Build (from the repo root; --root lets the deck read dbt/ outputs and seeds):
//   PDF : typst compile --root . presentation-2/slides.typ presentation-2/slides.pdf
//   PPTX: uvx --from touying touying compile --root . --format pptx \
//           presentation-2/slides.typ --output presentation-2/slides.pptx
// Refresh the numbers first with `uv run python presentation-2/make_data.py`.
//
// The PPTX holds one rendered image per slide plus the speaker notes, so edit here,
// not in PowerPoint. Notes are tagged with who presents: [KT], [ZW], [KL].

#import "@preview/touying:0.7.4": *
#import themes.simple: *
#import "@preview/lilaq:0.6.0" as lq
#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node

#let case-photo = "img/farnsworth.jpg"  // bostonofficespaces.com listing
#let case-map = "img/map.png"  // make_map.py

// ---- data ------------------------------------------------------------------

#let stats = json("data/stats.json")
#let outcomes = csv("data/outcomes.csv", row-type: dictionary)
// 20-year outcomes under the illustrative grid and price scenarios (dbt/seeds/energy_scenarios.csv)
#let scen = csv("../dbt/analysis_outputs/energy_scenario_outcomes.csv", row-type: dictionary)
#let case = csv("data/case_study.csv", row-type: dictionary)
#let breakeven = csv("../dbt/analysis_outputs/breakeven_acp.csv", row-type: dictionary,
  ).map(r => float(r.breakeven_acp_usd_per_t))
#let standards = csv("../dbt/seeds/berdo_emissions_standards.csv", row-type: dictionary).filter(r => (
  r.building_use == "Office"
))
// k-sensitivity of the cheapest compliant pick, with 5-year energy bills (dbt/financial_k_sensitivity.py).
// report/data/financial_k_summary.csv is an older run without energy costs; don't use it here.
#let ksens = csv("../dbt/analysis_outputs/financial_k_summary.csv", row-type: dictionary)
// leave-one-out validation of the matching on ComStock offices (dbt models analysis_loo_*)
#let loo = csv("../dbt/analysis_outputs/loo_k_summary.csv", row-type: dictionary)
#let lootest = csv("../dbt/analysis_outputs/loo_tests.csv", row-type: dictionary)
// Farnsworth's options over 2030-2034 (undiscounted 5-year screen)
#let farn = csv("data/farnsworth_options.csv", row-type: dictionary)
#let case-row(id) = case.find(r => r.upgrade_id == str(id))
#let farn-row(id) = farn.find(r => r.upgrade_id == str(id))

#let case-results = csv(
  "../dbt/analysis_outputs/case_study_106476.csv",
  row-type: dictionary,
)

#let money(x, digits: 0) = {
  let v = calc.round(float(x), digits: digits)
  let s = str(calc.abs(v))
  let (whole, frac) = if s.contains(".") { s.split(".") } else { (s, none) }
  let out = ""
  for (i, ch) in whole.clusters().rev().enumerate() {
    if i > 0 and calc.rem(i, 3) == 0 { out = "," + out }
    out = ch + out
  }
  (if v < 0 { "−" } else { "" }) + "$" + out + (if frac != none { "." + frac } else { "" })
}
#let thousands(x) = money(float(x) / 1000) + "k"

#let chart(body) = {
  set text(size: 12pt)
  body
}

// ---- look ------------------------------------------------------------------

#let ink = rgb("#0b0b0b")
#let ink-2 = rgb("#52514e")
#let muted = rgb("#8a8984")
#let rule = rgb("#d9d8d3")
#let navy = rgb("#1d3557")
// categorical slots from the dataviz reference palette (light), fixed order
#let c-blue = rgb("#2a78d6")
#let c-orange = rgb("#eb6834")
#let c-aqua = rgb("#1baf7a")
#let c-gray = rgb("#a8a7a1")
#let green-box = rgb("#e7f4ec")
#let green-edge = rgb("#2e7d4f")

// The five sections of the talk; a strip at the top shows where we are.
#let stops = ([The building], [Data science], [The decision], [Results], [Implications])

#let progress(at) = {
  set text(size: 9.5pt)
  grid(
    columns: stops.len(),
    column-gutter: 4pt,
    ..stops
      .enumerate()
      .map(((i, s)) => {
        let on = i + 1 == at
        let done = at != none and i + 1 < at
        block(width: 100%, {
          rect(width: 100%, height: 4pt, radius: 2pt, stroke: none, fill: if on { navy } else if done {
            navy.lighten(60%)
          } else { rule })
          v(-6pt)
          text(fill: if on { navy } else { muted }, weight: if on { "bold" } else { "regular" })[#(i + 1). #s]
        })
      }),
  )
}

// Green box at the bottom of a slide: the one sentence to remember.
#let takeaway(body) = block(
  width: 100%,
  inset: (x: 14pt, y: 9pt),
  radius: 6pt,
  fill: green-box,
  stroke: (left: 4pt + green-edge),
  text(size: 16pt, fill: ink)[#body],
)

// A content slide: progress strip, a title that states the point, then the body.
#let s(title, stop: none, body) = slide({
  if stop != none { progress(stop) } else { v(17pt) }
  v(4pt)
  text(size: 25pt, weight: "bold", fill: navy, title)
  v(6pt)
  body
})

#show: simple-theme.with(
  aspect-ratio: "16-9",
  header: none,
  footer: text(fill: muted)[DS5500 · Presentation 3 · Theodoropoulos, Wegrzyniak, Lysytsyna],
  primary: navy,
  subslide-preamble: none,
  config-page(paper: "presentation-16-9", margin: (x: 1.4cm, top: 0.9cm, bottom: 1.1cm)),
)

#set text(font: ("Fira Sans", "Libertinus Sans"), size: 16pt, fill: ink)
#show math.equation: set text(font: ("Fira Math", "New Computer Modern Math"))
#set par(leading: 0.6em)
#set list(spacing: 0.7em, marker: text(fill: navy)[•])
#set table(stroke: none, inset: (x: 8pt, y: 5pt))
#show table.cell.where(y: 0): set text(weight: "bold")
// Number and label every figure and table (feedback from Presentation 1).
#show figure.caption: it => text(size: 12pt, fill: ink-2)[
  #strong[#it.supplement #context it.counter.display(it.numbering).] #it.body
]
#set figure(gap: 8pt)

// ---- 1. title --------------------------------------------------------------

#slide({
  set align(horizon)
  text(size: 13pt, fill: muted, tracking: 1pt)[DS5500 CAPSTONE · PRESENTATION 3 · TEAM 7]
  v(10pt)
  text(size: 38pt, weight: "bold", fill: navy)[Should Boston office owners pay for emissions or invest in retrofits?]
  v(18pt)
  grid(
    columns: (auto, 1fr),
    column-gutter: 16pt,
    row-gutter: 14pt,
    text(size: 14pt, weight: "bold", fill: navy, tracking: 0.5pt)[DOMAIN \ PROBLEM],
    text(size: 19pt)[How can Boston office owners respond to BERDO's emissions limits at the lowest cost?],

    text(size: 14pt, weight: "bold", fill: green-edge, tracking: 0.5pt)[DATA SCIENCE \ PROBLEM],
    text(size: 19pt)[How can we estimate the impact of upgrades on real buildings without directly measuring it?],
  )
  v(28pt)
  text(size: 16pt)[Konstantinos Theodoropoulos · Zachary Wegrzyniak · Kateryna Lysytsyna]
  linebreak()
  text(size: 13pt, fill: muted)[github.com/wegry/DS5500]
})
#speaker-note[
  [KL] Our project is about a decision that many Boston building owners will have to make in the coming years: should they spend money upgrading their buildings, or is it cheaper to keep paying the city for excess emissions? We want to help owners choose the most cost-effective response to Boston's emissions rules: a retrofit or the ACP. And the cheapest option might not actually cut emissions enough to meet the standard.

  Before we can compare upgrades, we need to know what those upgrades would do to a building's energy and emissions. So our work is to estimate those outcomes first, and then use them to compare financial decisions.
]

// ---- 1b. glossary -----------------------------------------------------------

#let term(name, body) = block(
  width: 100%,
  inset: (left: 10pt, y: 5pt),
  stroke: (left: 3pt + navy.lighten(55%)),
  {
    text(size: 15pt, weight: "bold", fill: navy)[#name]
    linebreak()
    text(size: 13.5pt, fill: ink)[#body]
  },
)

#s([Eight terms we use throughout])[
  #grid(
    columns: (1fr, 1fr),
    column-gutter: 26pt,
    row-gutter: 14pt,
    term(
      [BERDO],
      [Boston's Building Emissions Reduction and Disclosure Ordinance. Large buildings report energy yearly and must stay under emissions limits that step down to zero by 2050.],
    ),
    term(
      [ComStock],
      [A national lab's simulations of U.S. commercial buildings, with energy use before and after each of dozens of retrofits.],
    ),

    term(
      [Emissions intensity & EUI],
      [kg CO#sub[2]e per ft² per year: what BERDO limits. The office limit is 5.3 now and 3.2 from 2030. Energy Use Intensity (EUI) measures energy consumption per ft² per year.],
    ),
    term(
      [Global cost],
      [Total cost over 20 years: equipment, energy bills and emissions cost, with future dollars discounted (EN 15459).],
    ),

    term(
      [ACP],
      [Alternative Compliance Payment: \$#stats.acp_usd_per_t per ton of CO#sub[2]e over the limit, every year. The "pay" option.],
    ),
    term(
      [Grid emissions factor],
      [kg CO#sub[2]e per kWh of electricity. BERDO's falls as the state's renewable requirement (RPS) rises.],
    ),

    term(
      [Retrofit package],
      [An upgrade to the building: LED lighting, insulation, windows, heat pumps. A package bundles several.],
    ),
    term(
      [RPS],
      [Renewable Portfolio Standard: Massachusetts' required share of new renewable power. 27% now, 40% by 2030.],
    ),
  )
]
#speaker-note[
  [KL] Before we start, a few terms we'll use a lot. BERDO is Boston's emissions rule for larger buildings. It limits emissions per square foot. The ACP is a payment for emissions above that limit, and paying it is one way to meet BERDO obligations. A retrofit package combines upgrades, like insulation or heat pumps. ComStock is the national lab's simulation data we borrow retrofit effects from. Global cost means comparing costs over 20 years. And the grid emissions factor tells us how much carbon is counted for electricity use.
]

// ---- 2. the decision in one slide ------------------------------------------

#s([#stats.over_limit of #stats.matched Boston offices must pay or retrofit by 2030], stop: 1)[
  #set text(size: 15pt)
  #grid(
    columns: (1fr, auto, 1.25fr),
    column-gutter: 18pt,
    align: (left + top, center + horizon, left + top),
    {
      text(size: 21pt, weight: "bold", fill: c-gray.darken(30%))[Pay]
      v(4pt)
      [An *Alternative Compliance Payment (ACP)*: *\$#stats.acp_usd_per_t per ton* of CO#sub[2] over the limit, every year @berdo-acp.]
      v(6pt)
      text(
        fill: ink-2,
      )[Cheap now. Grows as the limit steps down every five years: 3.2 → 2.4 → 1.6 → 0.8 → 0 kg/ft² @berdo-standards.]
      v(6pt)
      text(
        size: 13pt,
        fill: ink-2,
      )[#stats.over_limit are over the limit as BERDO will count emissions in 2030, with its projected grid factor @berdo-grid; #stats.over_limit_today at today's.]
    },
    text(size: 24pt, fill: muted)[vs.],
    {
      text(size: 21pt, weight: "bold", fill: c-blue)[Retrofit]
      figure(
        table(
          columns: (auto, 1fr),
          align: (left, left),
          inset: (x: 6pt, y: 4pt),
          table.hline(stroke: 0.8pt),
          table.header([], [Retrofit]),
          table.hline(stroke: 0.5pt),
          [Single], [LED · wall / roof insulation · windows · PV],
          [HVAC], [VRF with DOAS · ground-source heat pump],
          [Pkg 1], [Envelope: walls + roof + windows],
          [Pkg 2, 4], [LED + heat pumps (high / standard efficiency)],
          [Pkg 3], [Pkg 1 + Pkg 2],
          [Pkg 5], [Heat pumps + ventilation upgrades],
          [Pkg 12], [Rooftop PV + roof insulation],
          table.hline(stroke: 0.8pt),
        ),
        caption: [13 of the 23 retrofits in our analysis, from ComStock @comstock.],
      )
    },
  )
  #v(1fr)
  #takeaway[Retrofitting costs more up front and saves every year after. *So the answer depends on how far ahead you look.*]
]

#speaker-note[
  [KT] Now that we've introduced BERDO, let's look at what this means for building owners. Of the 297 office buildings in our analysis, 81 will be above the 2030 limit as BERDO counts emissions in 2030. At today's grid factor it would be 99, but by 2030 BERDO counts each kilowatt-hour of electricity as about 15 percent cleaner, because the state's renewable standard rises.

  Their owners face a choice. They can invest in upgrades, such as better insulation, LED lighting, or heat pumps, to reduce their emissions. Or they can continue operating above the limit and make an Alternative Compliance Payment
  of 234 for every metric ton of excess emissions each year. The important distinction is that retrofits require an upfront investment, while ACPs are recurring and can increase as emissions limits become stricter.

  So the question we're trying to answer is: which option is more cost-effective, and does the cheapest option actually reduce emissions enough to meet the standard?
]

// ---- 3. case study: building and missing outcome -------------------------

#s([24 Farnsworth St: estimating the impact of a retrofit], stop: 1)[
  #let today = float(stats.case_intensity)
  #let as-is = float(case-row(0).intensity)
  #let projected = float(case-row(55).intensity)

  #grid(
    columns: (0.85fr, 1.4fr),
    column-gutter: 22pt,
    align: (left + top, left + top),

    {
      figure(
        image(case-photo, width: 100%, height: 6cm, fit: "cover"),
        caption: [24 Farnsworth St, Boston @bos-listing.],
      )

      v(4pt)
      set text(size: 14pt)
      grid(
        columns: (auto, 1fr),
        column-gutter: 12pt,
        row-gutter: 7pt,
        [*Built*], [1915],
        [*Floor area*], [#str(calc.round(stats.case_gfa_sqft / 1000))k ft²],
        [*Energy*], [65% natural gas],
      )
    },

    {
      set block(spacing: 6pt)
      text(size: 16pt, weight: "bold")[GHG intensity (kg CO#sub[2]e/ft²/yr)]
      v(6pt)

      // Horizontal bars: reported vs. estimated
      for (name, value, color) in (
        ("Reported today", today, navy),
        ("2030, no retrofit: BERDO's grid factor", as-is, c-gray.darken(20%)),
        ("2030, LED + heat pumps: estimated", projected, c-blue),
      ) {
        text(size: 12.5pt, weight: "bold")[#name]
        v(0pt)
        grid(
          columns: (1fr, 45pt),
          column-gutter: 10pt,
          align: (left + horizon, right + horizon),
          block(
            width: 100%,
            height: 14pt,
            fill: rgb("#f0f0ee"),
            rect(
              width: 100% * value / 5.6,
              height: 14pt,
              fill: color,
              stroke: none,
            ),
          ),
          text(size: 15pt, weight: "bold")[#str(calc.round(value, digits: 2))],
        )
        v(2pt)
      }

      line(length: 100%, stroke: 1pt + rule)
      v(2pt)
      text(size: 14pt, fill: c-orange.darken(15%))[
        *2030 BERDO limit: 3.2 kg CO#sub[2]e/ft²/yr*
      ]
      v(2pt)
      text(size: 12pt, fill: ink-2)[
        2030 counts electricity at BERDO's projected factor. The retrofit is a
        ComStock-based estimate, not an observed outcome.
      ]
    },
  )

  #v(8pt)
  #takeaway[
    We know current emissions. Our challenge is to estimate
    *how each retrofit would change them.*
  ]
]
#speaker-note[
  [ZW] Let's look at 24 Farnsworth Street, an office building in
  Boston built in 1915. It's roughly 79,000 square feet, and
  natural gas accounts for about 65 percent of its energy use.

  Its reported emissions intensity is 4.8. By 2030 BERDO counts
  its electricity as cleaner, which alone brings it to about 4.55,
  still above the 2030 limit of 3.2. Our model estimates that LED
  lighting and heat pumps would bring it to about 2.08.

  But there's an important distinction: 4.8 is reported data,
  while 2.08 is an estimate. We haven't observed this retrofit
  happening. Estimating those outcomes is the data science
  problem we're trying to solve.
]


// ---- 4. three datasets used ---------------------------------------

#let dcard(accent, title, grain, has, lacks) = block(
  width: 100%,
  height: 4.4cm,
  inset: (left: 10pt, rest: 8pt),
  radius: (right: 4pt),
  stroke: (left: 4pt + accent, rest: 0.6pt + rule),
  align(left)[
    #text(size: 17pt, weight: "bold", fill: accent)[#title] \
    #text(size: 12pt, fill: ink-2)[1 row = #grain] \
    #v(3pt)
    #text(size: 13pt)[*Has:* #has] \
    #text(size: 13pt, fill: ink-2)[*Lacks:* #lacks]
  ],
)
#let darrow(label) = align(center + horizon, text(size: 12pt, fill: navy)[#label \ #text(size: 20pt)[⟶]])

#s([Three datasets help us estimate retrofit costs and savings], stop: 2)[
  #set text(size: 15pt)
  #figure(
    {
      grid(
        columns: (1fr, 2.6cm, 1fr, 2.6cm, 1fr),
        dcard(
          navy,
          [BERDO @berdo],
          [1 real Boston building],
          [floor area, energy by fuel, reported emissions],
          [what a retrofit would do],
        ),
        darrow[k-nearest- \ neighbor match],
        dcard(
          green-edge,
          [ComStock @comstock],
          [1 simulated building × upgrade],
          [energy by fuel, before and after each upgrade],
          [any real address],
        ),
        darrow[component \ mapping],
        dcard(
          c-orange,
          [BTB @btb],
          [1 retrofit component],
          [installed cost (low / mid / high), lifetime],
          [any building],
        ),
      )
      align(center, text(size: 20pt, fill: navy)[↓])
      v(-4pt)
      align(center, block(
        inset: 8pt,
        radius: 4pt,
        fill: green-box,
        stroke: 0.8pt + green-edge,
        align(center)[#text(size: 14pt, weight: "bold")[1 row per real building × option] \ #text(
            size: 12.5pt,
            fill: ink-2,
          )[projected emissions · installed cost · energy bill · ACP]],
      ))
    },
    caption: [How the three sources combine in the dbt pipeline (github.com/wegry/DS5500/tree/main/dbt).],
  )
  #v(16pt)
  #takeaway[Not a database join: *retrofit effects transfer by matching, costs by component mapping.*]
]
#speaker-note[
  [KT] So, how do we estimate the impact of a retrofit that hasn't happened yet? To answer that question, we bring together three datasets, each providing a different piece of the puzzle.

  First, BERDO gives us real-world information about Boston buildings, including their size, energy consumption, and reported emissions. This establishes our starting point.

  Second, ComStock, developed by the National Laboratory of the Rockies, simulates how different building upgrades affect energy consumption and emissions. This allows us to estimate the impact of retrofits that haven't actually taken place.

  Finally, the Building Technology Baselines, or BTB, provides cost estimates for different building technologies and upgrades.

  Together, these datasets give us the information we need to estimate retrofit outcomes for real Boston buildings. The next challenge is figuring out how to match those buildings with the appropriate simulations.
]

// ---- 5. matching ------------------------------------------------------------

#let mnode(pos, title, detail, name, fill: white) = node(
  pos,
  align(center)[#text(size: 13pt, weight: "bold")[#title] \ #text(size: 11.5pt, fill: ink-2)[#detail]],
  name: name,
  width: 4.4cm,
  height: 2cm,
  inset: 5pt,
  corner-radius: 4pt,
  stroke: 0.8pt + navy,
  fill: fill,
)

#s([Similar simulated buildings help us predict retrofit outcomes], stop: 2)[
  #set text(size: 15pt)
  #figure(
    diagram(
      spacing: (10pt, 10pt),
      edge-stroke: 1pt + navy,
      mnode((0, 0), [① Real office], [from BERDO], <b>, fill: green-box),
      mnode((1, 0), [② Filter], [same type and district-energy status], <f>),
      mnode((2, 0), [③ Most similar], [size, EUI, fuel mix, stories], <d>),
      mnode((3, 0), [④ Keep 20], [weight closer matches more], <k>),
      mnode((4, 0), [⑤ Apply], [to the real building's own emissions], <r>, fill: green-box),
      edge(<b>, <f>, "-|>"),
      edge(<f>, <d>, "-|>"),
      edge(<d>, <k>, "-|>"),
      edge(<k>, <r>, "-|>"),
    ),
    caption: [Matching each real building to its 20 most similar simulated buildings (k-nearest neighbors). Read left to right.],
  )
  #v(2pt)
  #grid(
    columns: (auto, 1fr),
    column-gutter: 18pt,
    row-gutter: 12pt,
    align: (left + horizon, left + horizon),
    text(size: 13pt, weight: "bold", fill: green-edge)[MATCH],
    text(size: 16pt)[$
      d(b,c) = underbrace(abs(ln A_b/A_c), "size")
      + underbrace(abs(ln "EUI"_b/"EUI"_c), "energy per ft²")
      + underbrace(1/2 sum_f abs(s_(b,f) - s_(c,f)), "fuel mix")
      + underbrace(abs(ln S_b/S_c), "stories")
    $],

    text(size: 13pt, weight: "bold", fill: green-edge)[PREDICT],
    text(size: 16pt)[$
      hat(G)_b = sum_f G_(b,f) dot r_f,
      quad r_f = (sum_(c in N_b) w_(b c) U_(c,f)) /
      (sum_(c in N_b) w_(b c) B_(c,f))
    $],
  )
  #align(center, text(
    size: 12.5pt,
    fill: ink-2,
  )[$b$ = real building, $c$ = simulated one, $A$ = floor area, $S$ = stories, $N_b$ = its 20 matches. $G_(b,f)$ = reported emissions from fuel $f$; $U$, $B$ = simulated use after / before the upgrade. $w_(b c) = 1 / (d(b,c) + 10^(-6))$ gives closer matches more weight.])
  #v(1fr)
  #takeaway[We keep each building's *real* emissions and borrow only the *% change* from its simulated neighbors.]
]
#speaker-note[
  [KL] Here's how we make those predictions. We match each real BERDO office to simulated ComStock offices that look similar in size, energy use per square foot, fuel mix, and number of stories. We also make sure they have the same district-energy use status.

  We keep the twenty closest matches and give more weight to the ones that are most similar. Then we look at how an upgrade changes energy use in those simulations. For example, heat pumps might reduce gas use but increase electricity use.

  We combine the changes for each fuel across the matches and apply them to the real building's reported emissions. So we're not copying a simulated building's final result. We're borrowing the estimated change to predict what might happen to the real building.
]

// ---- 6. sensitivity to k ----------------------------------------------------

#s([Matching similar buildings improves retrofit predictions], stop: 2)[
  #let num = loo.filter(r => r.k not in ("all", "type"))
  #let ks = num.map(r => int(r.k))
  #let mae = num.map(r => float(r.mae_pp))
  #let kmax = ks.last()  // floor(sqrt(number of office models)), set in analysis_loo_predictions
  #let at(k) = float(loo.find(r => r.k == k).mae_pp)
  #let t-all = lootest.find(r => r.comparison == "k=10 minus all")
  #let row(k) = ksens.find(r => r.k == str(k))
  #let stab9 = int(row(9).different_recommendations) / float(row(9).compliant_buildings_compared) * 100
  #grid(
    columns: (1.45fr, 1fr),
    column-gutter: 20pt,
    figure(
      chart(lq.diagram(
        width: 14cm,
        height: 6cm,
        xlim: (0, kmax + 1),
        ylim: (6.4, 8.0),
        xlabel: [Neighbors kept ($k$)],
        ylabel: [Mean error (pct-pts of emissions cut)],
        xaxis: (ticks: (1, 5, 10, 15, 20, kmax), subticks: none),
        yaxis: (subticks: none),
        grid: none,
        lq.hlines(at("all"), stroke: (paint: c-gray.darken(20%), thickness: 1.2pt, dash: "dashed")),
        lq.hlines(at("type"), stroke: (paint: c-orange, thickness: 1.2pt, dash: "dashed")),
        lq.place(kmax + 0.6, at("all"), align: bottom + right, pad(bottom: 2pt, text(
          size: 11pt,
          fill: ink-2,
        )[No matching: all other offices])),
        lq.place(kmax + 0.6, at("type"), align: bottom + right, pad(bottom: 2pt, text(
          size: 11pt,
          fill: c-orange.darken(15%),
        )[Office size class only])),
        lq.plot(ks, mae, stroke: 2pt + navy, mark: "o", mark-size: 4pt, color: navy),
        lq.plot((20,), (at("20"),), stroke: none, mark: "o", mark-size: 9pt, color: c-blue),
        lq.place(20, at("20"), align: top + center, pad(top: 9pt, text(
          size: 11.5pt,
          weight: "bold",
          fill: c-blue,
        )[$k = 20$: #at("20")])),
      )),
      caption: [Leave-one-out validation on 618 simulated Boston offices: hide one, predict its emissions reduction for each of the 23 retrofits, and compare with ComStock's known result.],
    ),
    {
      set text(size: 14.5pt)
      v(10pt)
      list(
        [Matching reduces average prediction error from *7.55* to *6.65* percentage points, an improvement of approximately 12%.],
        [Prediction error levels off around $k = 20$, supporting our choice of 20 neighbors with inverse-distance weighting.],
        [Matching correctly identifies whether a compliant retrofit exists for *88.7%* of buildings over the limit, compared with *76.5%* without matching.],
      )
    },
  )
  #v(6pt)
  #takeaway[Matching measurably helps. But this is error *between simulations*, not against real retrofits.]
]
#speaker-note[
  [ZW] To evaluate our matching methodology, we hide each of the 618 simulated Boston offices in turn and treat it as if it were a real building. We predict its emissions reduction for each of the 23 retrofit options and compare our predictions with ComStock's known results.

  The graph shows how prediction error changes as we increase the number of neighbors. With 20 neighbors, our average error is 6.65 percentage points, approximately 12 percent lower than if we didn't match buildings at all. Beyond 20 neighbors, there is little additional improvement.

  More importantly, matching helps us answer our original domain question. For simulated buildings above the emissions limit, we correctly identify whether a compliant retrofit exists almost 89 percent of the time, compared with 77 percent without matching.

  The important caveat is that these tests are conducted on simulated buildings. Without observed real-world retrofit outcomes, we cannot yet establish how accurate our predictions are for actual Boston offices.
]

// ---- 7. the five-year decision rule ----------------------------------------

#s([The cheapest retrofit is not always enough to meet the emissions limit], stop: 3)[
  #set text(size: 15pt)
  #grid(
    columns: (auto, 1fr),
    column-gutter: 20pt,
    row-gutter: 9pt,
    align: (left + horizon, left + horizon),

    text(size: 13pt, weight: "bold", fill: navy)[OPTIONS],
    [23 retrofit options + no retrofit = *24 alternatives*],

    text(size: 13pt, weight: "bold", fill: navy)[EQUIPMENT],
    [Installation, replacement and remaining equipment value],

    text(size: 13pt, weight: "bold", fill: navy)[ENERGY],
    [Projected annual electricity and fuel bills],

    text(size: 13pt, weight: "bold", fill: navy)[EMISSIONS],
    [Compliance payments or societal climate damages],

    text(size: 13pt, weight: "bold", fill: navy)[HORIZON],
    [20 years (2027–2046)],
  )
  #v(12pt)
  #grid(
    columns: (1fr, 1fr),
    column-gutter: 20pt,
    block(
      inset: 10pt,
      radius: 4pt,
      stroke: (left: 4pt + c-orange),
      [*Cheapest overall:* lowest total cost, regardless of emissions.],
    ),
    block(
      inset: 10pt,
      radius: 4pt,
      stroke: (left: 4pt + c-blue),
      [*Cheapest under the limit:* lowest total cost while meeting the 2030 emissions standard.],
    ),
  )
  #v(1fr)
  #takeaway[We evaluate both economic attractiveness and environmental performance.]
]
#speaker-note[
  [KT] Now that we can estimate the impact of different retrofits, the next question is which option a building owner should choose.

  For each building, we evaluate 24 alternatives, including 23 retrofit options and the option of doing nothing.

  We compare their total costs over a 20-year period, accounting for equipment costs, projected energy bills, and emissions-related costs.

  We then identify two outcomes: the cheapest option overall and the cheapest option that actually brings the building under the 2030 emissions limit.

  However, the definition of cost depends on whose perspective we take. A decision that minimizes costs for a building owner may not necessarily minimize costs for society.
]

// ---- 8. the 20-year method, owner vs society --------------------------------

#s([Emissions have different costs for owners and society], stop: 3)[
  #set text(size: 15pt)
  #align(center, block(inset: 8pt, radius: 6pt, stroke: 0.6pt + rule, text(size: 16pt)[
    $
      "Cost" = underbrace(C_"equipment", "install + replace" \ "− value left at yr 20")
      + sum_(t=1)^(20) (overbrace(E_t, "energy bills" \ "in year" t) + overbrace(P_t, "emissions cost" \ "in year" t)) / underbrace((1+r)^t, "future dollars" \ "count less")
    $
  ]))
  #v(8pt)
  #figure(
    table(
      columns: (auto, 1fr, 1fr),
      align: (left, left, left),
      inset: (x: 8pt, y: 4pt),
      table.hline(stroke: 0.8pt),
      table.header([], [Owner's view], [Society's view]),
      table.hline(stroke: 0.5pt),

      [Emissions cost $P_t$],
      [\$234 per ton *above the limit* (ACP).],
      [\$281 per ton on *all emissions* (social cost of carbon) @epa-scghg.],

      [What it represents],
      [Financial payment to the City of Boston.],
      [Estimated economic damage caused by emissions. ACPs are excluded because they are financial transfers.],

      [Discount rate $r$],
      [7% (private cost of capital)],
      [2% (consistent with the carbon damage estimate)],

      table.hline(stroke: 0.8pt),
    ),
    caption: [EN 15459 global cost @en15459, as in the EU cost-optimal method @eu-cost-optimal. Equipment lifetimes from BTB @btb.],
  )
  #v(1fr)
  #takeaway[Emissions impose real economic costs through impacts on health, agriculture and infrastructure.
  ]
]
#speaker-note[
  [ZW] We calculate the total cost of each option over 20 years using the European global cost method. This includes installing and replacing equipment, its remaining value at the end of the period, annual energy bills, and emissions-related costs.

  The key difference is how we value emissions. Under BERDO, owners pay 234 dollars for every ton above their emissions limit. However, emissions below that limit still cause climate damage.

  To account for this, we use the social cost of carbon, which estimates the economic damage caused by emitting an additional ton. This includes impacts on human health, agriculture, infrastructure and the wider economy. Using the EPA's 2023 estimate, adjusted for inflation, we value these damages at 281 dollars per ton.

  We exclude compliance payments from society's costs because they represent money moving from the owner to the city, rather than an additional cost to society as a whole.

  These two perspectives can therefore lead to very different retrofit recommendations.
]

// ---- 9. answer: BERDO's grid factor and energy prices -------------------------

#s([A cleaner electricity grid matters more than future energy prices], stop: 4)[
  // owner's view, one bar per scenario; the two decomposition scenarios go in the bullets
  #let shown = ("frozen", "projected", "lowogs", "highogs", "higheldmd")
  #let row(sc, p) = scen.find(r => r.scenario == sc and r.perspective == p)
  #let own = shown.map(sc => row(sc, "financial"))
  #let n = own.len()
  #let ys = range(n).rev()  // first scenario on top
  #let asc(arr) = arr.rev()
  #let col(rs, k) = rs.map(r => float(r.at(k)))
  #let u = col(own, "under_limit_anyway")
  #let a = col(own, "no_retrofit")
  #let o = col(own, "retrofit_over")
  #let g = col(own, "retrofit_compliant")
  #let cum(..parts) = range(n).map(i => parts.pos().map(p => p.at(i)).sum())
  #let ua = cum(u, a)
  #let uao = cum(u, a, o)
  #let uaog = cum(u, a, o, g)
  #let soc(sc) = int(row(sc, "societal").retrofit_compliant)
  #let comp = col(own, "retrofit_compliant").slice(1).map(int)
  #let swatch(c, t) = box(baseline: 1pt, rect(width: 11pt, height: 11pt, radius: 2pt, fill: c)) + h(4pt) + t
  #let labels = (
    [Today's levels],
    [AEO baseline],
    [High prices#super[a]],
    [Low prices#super[b]],
    [Data-center demand#super[c]],
  )
  #align(center, text(
    size: 12.5pt,
    swatch(c-aqua, [Under the limit anyway])
      + h(14pt)
      + swatch(c-gray, [Just pay])
      + h(14pt)
      + swatch(c-orange, [Retrofit, still over])
      + h(14pt)
      + swatch(c-blue, [Retrofit, under the limit]),
  ))
  #v(-4pt)
  #grid(
    columns: (1.55fr, 1fr),
    column-gutter: 16pt,
    figure(
      chart(lq.diagram(
        width: 11.2cm,
        height: 4.6cm,
        xlim: (0, stats.over_limit_today),
        ylim: (-0.6, n - 0.4),
        xlabel: [Offices over the limit at today's factor (of #stats.over_limit_today): owner's cheapest 20-year option],
        yaxis: (ticks: ys.zip(labels), subticks: none),
        xaxis: (ticks: (0, 25, 50, 75, stats.over_limit_today), subticks: none),
        grid: none,
        lq.hbar(asc(u), asc(ys), fill: c-aqua, stroke: 1.5pt + white, width: 0.62),
        lq.hbar(asc(ua), asc(ys), base: asc(u), fill: c-gray, stroke: 1.5pt + white, width: 0.62),
        lq.hbar(asc(uao), asc(ys), base: asc(ua), fill: c-orange, stroke: 1.5pt + white, width: 0.62),
        lq.hbar(asc(uaog), asc(ys), base: asc(uao), fill: c-blue, stroke: 1.5pt + white, width: 0.62),
        ..range(n)
          .map(i => ((u.at(i), 0), (o.at(i), ua.at(i)), (g.at(i), uao.at(i)))
            .filter(((v, b)) => v >= 3)
            .map(((v, b)) => lq.place(b + v / 2, ys.at(i), text(size: 11.5pt, weight: "bold", fill: white)[#int(v)])))
          .flatten(),
      )),
      caption: [Limit and ACP: BERDO projected grid factor @berdo-grid × (1 − RPS Class I @ma-rps). Bills: AEO2026 New England commercial prices @aeo2026 (#super[a]low and #super[b]high oil & gas supply, #super[c]high electricity demand). Society's grid: Cambium 2024 mid-case @cambium.],
    ),
    {
      set text(size: 14pt)
      v(6pt)
      list(
        [*#int(u.at(1))* of #stats.over_limit_today offices fall under the 2030 limit without a retrofit, as BERDO counts electricity emissions as progressively lower.],
        [Among the remaining offices, *#calc.min(..comp)–#calc.max(..comp)* choose compliant retrofits across the projected energy price scenarios.],
        [Changing energy prices alone leaves the owner's compliant count unchanged at *#int(row("prices_only", "financial").retrofit_compliant)* offices.],
        [From society's perspective, 44–47 offices choose compliant retrofits across the projected price scenarios.],
      )
    },
  )
  #v(1fr)
  #takeaway[BERDO's projected electricity emissions have a greater impact on 2030 compliance than the energy price scenarios we evaluated.]
]
#speaker-note[
  [KL] This slide shows how future electricity emissions and energy prices affect our retrofit recommendations.

  The top bar represents today's conditions, where 99 offices exceed the 2030 emissions limit. Of those, 42 would choose a retrofit that meets the limit.

  However, BERDO projects lower emissions per unit of electricity, partly because Massachusetts requires an increasing share of renewable energy. Under these projections, 18 offices meet the 2030 limit without making any changes to their buildings.

  Among the remaining 81 offices, between 35 and 37 choose compliant retrofits across our different energy price scenarios.

  We also tested changing energy prices alone, which left the number of compliant owner recommendations unchanged.

  This suggests that BERDO's projected electricity emissions have a much greater impact on compliance outcomes than the energy price scenarios we evaluated.
]

// ---- 10. answer: the case --------------------------------------------------

#s([Back to Farnsworth: cutting emissions also minimizes costs], stop: 4)[
  #let opts = (
    (15, [Heat pump boiler], green),
    (55, [Package 2], c-blue),
    (21, [Air-handler recovery], c-orange),
  )
  #let lenses = (
    ("financial", [Owner]),
    ("societal", [Society]),
  )
  #let xs = range(lenses.len())
  #let swatch(c, t) = box(
    baseline: 1pt,
    rect(width: 11pt, height: 11pt, radius: 2pt, fill: c),
  ) + h(4pt) + t

  #grid(
    columns: (1.35fr, 1fr),
    column-gutter: 20pt,
    figure(
      {
        align(center, text(
          size: 11pt,
          opts.map(((_, name, color)) => swatch(color, name))
            .join(h(10pt)),
        ))
        v(-2pt)
        chart(lq.diagram(
          width: 13cm,
          height: 6cm,
          xlim: (-0.6, 1.6),
          ylim: (0, 1450),
          ylabel: [Savings vs. no retrofit (\$ thousands)],
          xaxis: (
            ticks: xs.zip(lenses.map(l => l.at(1))),
            subticks: none,
          ),
          yaxis: (subticks: none, exponent: 0),
          grid: none,
          ..opts
            .enumerate()
            .map(((j, (id, name, color))) => {
              let vals = lenses.map(l => {
                let r = case-results.find(r =>
                  r.upgrade_id == str(id)
                  and r.perspective == l.at(0)
                )
                float(r.savings_vs_no_upgrade_usd) / 1000
              })
              (
                lq.bar(
                  xs, vals,
                  offset: (j - 1) * 0.25,
                  width: 0.23,
                  fill: color,
                  stroke: none,
                ),
                ..xs.map(i => lq.place(
                  i + (j - 1) * 0.25,
                  vals.at(i),
                  align: bottom,
                  pad(y: 3pt, text(size: 11pt, fill: ink)[
                    #calc.round(vals.at(i))k
                  ]),
                )),
              )
            })
            .flatten(),
          lq.hlines(0, stroke: 1.2pt + ink),
        ))
      },
      caption: [
        24–32 Farnsworth St: discounted savings over 2027–2046 compared with no retrofit, at baseline
        energy prices and mid installation costs.
      ],
    ),
    {
      set text(size: 14.5pt)
      v(10pt)
      list(
        [*Heat pump boiler with electric backup:* cheapest from both perspectives.],
        [Approximately *\$515k* in installation costs.],
        [*55.7% reduction* in projected 2030 emissions, bringing intensity from 4.55 to 2.02 kg CO#sub[2]e/ft².],
        [Meets the 2030 emissions limit of 3.2.],
      )
    },
  )
  #v(12pt)
  #takeaway[
    At Farnsworth, the same retrofit minimizes owner and societal costs while meeting the 2030 emissions limit.
  ]
]
#speaker-note[
  [ZW] Let's return to our example building at Farnsworth Street.

  With our updated methodology, the cheapest option from both the owner's and society's perspectives is a heat pump boiler with electric backup.

  Although installation costs approximately 515 thousand dollars, the retrofit saves the owner 261 thousand dollars over 20 years compared with doing nothing. When we account for societal costs, those savings increase to approximately 1.26 million dollars.

  The retrofit also reduces projected 2030 emissions by nearly 56 percent, bringing the building comfortably below the 2030 emissions limit.

  In this case, the financial and environmental objectives align. But as we'll see across our entire portfolio of office buildings, that isn't always the case.
]

// --------- 11. Portfolio-level results -------------------------------------

#s([Retrofits save money, but often fall short of compliance], stop: 4)[

  #set par(spacing: 12pt)

  #let result-bar(label, n, color) = {
    text(size: 13pt, weight: "medium")[#label]
    v(3pt)
    grid(
      columns: (1fr, 28pt),
      column-gutter: 8pt,
      align: horizon,
      box(width: 100%)[
        #rect(
          width: 100%,
          height: 20pt,
          fill: rgb("#eaeaea"),
          radius: 2pt,
          stroke: none,
        )
        #place(top + left)[
          #rect(
            width: n / 81 * 100%,
            height: 20pt,
            fill: color,
            radius: 2pt,
            stroke: none,
          )
        ]
      ],
      text(size: 16pt, weight: "bold", fill: navy)[#n],
    )
    v(10pt)
  }

  #grid(
    columns: (0.85fr, 1.15fr),
    column-gutter: 30pt,
    {
      text(size: 17pt, weight: "bold", fill: navy)[
        Total 20-year savings
      ]
      v(12pt)

      text(size: 38pt, weight: "bold", fill: green-edge)[\$39M]
      linebreak()
      text(size: 15pt)[From the owner's perspective]

      v(16pt)

      text(size: 38pt, weight: "bold", fill: green-edge)[\$103M]
      linebreak()
      text(size: 15pt)[From society's perspective]

      v(12pt)
      text(size: 11pt, fill: muted)[
        Compared with no retrofit, across 81 offices.
      ]
    },
    {
      text(size: 17pt, weight: "bold", fill: navy)[
        Offices meeting the 2030 limit
      ]
      v(10pt)

      result-bar([Have a compliant option], 71, muted)
      result-bar([Society's cheapest option], 46, green-edge)
      result-bar([Owner's cheapest option], 35, c-blue)

      text(size: 11pt, fill: muted)[
        Out of 81 offices exceeding the projected 2030 emissions limit.
      ]
    },
  )

  #v(1fr)
  #takeaway[
    A compliant retrofit is available for 71 offices in our model, but it is the cheapest choice for only 35 owners.
  ]
]
#speaker-note[
  [??] Looking beyond Farnsworth, we find that investing in a retrofit is cheaper than doing nothing for all 81 offices exceeding the projected 2030 emissions limit, from both perspectives.

  Over 20 years, these investments could generate 39 million dollars in savings for building owners and 103 million dollars in savings for society.

  However, the cheapest option isn't always enough to meet the emissions limit. While 71 offices have a modeled compliant retrofit, only 35 would choose one based on the owner's costs. When we account for climate damages, that number increases to 46.

  This raises an important policy question: are the current compliance payments high enough to incentivize deeper emissions reductions?
]

// ---- 12. answer: break-even ACP -------------------------------------------

#s([Increasing ACPs could lead to deeper emissions reductions], stop: 5)[
  // Empirical CDF of the break-even ACP, counted out of all over-limit offices, so the
  // ones with no compliant retrofit show as the gap between the curve's top and the total.
  #let xmax = 3000
  #let be = breakeven.sorted()
  #let n-opt = be.len()
  #let shown = be.filter(v => v <= xmax)
  #let above = n-opt - shown.len()
  #let today = stats.acp_usd_per_t
  #let at-today = be.filter(v => v <= today).len()
  #let mid = calc.floor(be.len() / 2)
  #let med = if calc.odd(be.len()) {
    be.at(mid)
  } else {
    (be.at(mid - 1) + be.at(mid)) / 2
  }
  // step: end holds each count until the next break-even value
  #let xs = (0,) + shown + (xmax,)
  #let ys = (0,) + range(1, shown.len() + 1) + (shown.len(),)
  #grid(
    columns: (1.45fr, 1fr),
    column-gutter: 20pt,
    figure(
      chart(lq.diagram(
        width: 14cm,
        height: 6cm,
        xlim: (0, xmax),
        ylim: (0, stats.over_limit + 9),
        xlabel: [ACP rate (\$ per ton)],
        ylabel: [Offices choosing compliant retrofits],
        xaxis: (
          ticks: (0, 500, 1000, 1500, 2000, 2500, 3000).map(t => (t, [\$#if t >= 1000 [#(t / 1000)k] else [#t]])),
          subticks: none,
        ),
        yaxis: (ticks: (0, 20, 40, 60, stats.over_limit), subticks: none),
        grid: none,
        // all over-limit offices, and the most the curve can reach
        lq.hlines(stats.over_limit, stroke: 0.8pt + rule),
        lq.hlines(n-opt, stroke: (paint: c-gray.darken(20%), thickness: 1pt, dash: "dotted")),
        lq.place(xmax - 40, (n-opt + stats.over_limit) / 2, align: horizon + right, text(
          size: 11pt,
          fill: ink-2,
        )[↕ #(stats.over_limit - n-opt) offices: no retrofit gets under the limit]),
        lq.place(xmax - 40, stats.over_limit, align: bottom + right, pad(bottom: 2pt, text(
          size: 11pt,
          fill: ink-2,
        )[All #stats.over_limit over the limit])),
        lq.vlines(today, stroke: (paint: c-blue, thickness: 1.5pt, dash: "dashed")),
        // median drawn only up to the curve, so it does not cut through the "Today" label
        lq.plot((med, med), (0, be.filter(v => v <= med).len()), mark: none, stroke: (
          paint: c-orange,
          thickness: 1.2pt,
          dash: "dashed",
        )),
        lq.plot(xs, ys, step: end, mark: none, stroke: 2.2pt + navy),
        lq.plot((today,), (at-today,), stroke: none, mark: "o", mark-size: 8pt, color: c-blue),
        lq.place(today, (n-opt + stats.over_limit) / 2, align: horizon + left, pad(left: 5pt, text(
          size: 11.5pt,
          fill: c-blue,
          weight: "bold",
        )[Today: \$#today → #at-today])),
        lq.place(med, 4, align: bottom + left, pad(left: 5pt, text(
          size: 11.5pt,
          fill: c-orange.darken(15%),
          weight: "bold",
        )[Median: \$#calc.round(med)])),
        lq.place(xmax - 40, shown.len(), align: top + right, pad(top: 4pt, text(
          size: 11pt,
          fill: ink-2,
        )[+#above more above \$3k])),
      )),
      caption: [Over-limit offices whose cheapest 20-year option (owner's view) is a retrofit under the limit, as the ACP rises. Each step is one building's break-even rate.],
    ),
    {
      set text(size: 14.5pt)
      v(10pt)
      list(
        [Even without ACPs, a compliant retrofit is cheapest for *#(be.filter(v => v == 0).len())* offices.],

        [At today's *\$#today/t*, a compliant retrofit is cheapest for *#at-today* of #stats.over_limit offices.],

        [At *\$1,000/t*, that number rises to *#(be.filter(v => v <= 1000).len())*.],

        [For *#(stats.over_limit - n-opt)* offices, none of the evaluated retrofits meets the 2030 limit.],
      )
    },
  )
  #v(12pt)
  #takeaway[Stronger financial incentives could encourage compliance, but some buildings need more effective retrofit options.
  ]
]
#speaker-note[
  [KT] Our results raise an interesting policy question: how much would compliance payments need to increase before meeting the emissions limit becomes the cheapest choice?

  To investigate this, we calculate the break-even payment for each building with a compliant retrofit option.

  Interestingly, even without compliance payments, meeting the limit is the cheapest choice for 29 offices. At today's rate of 234 dollars per ton, that number increases to 35. At a hypothetical rate of 1,000 dollars per ton, it reaches 50.

  However, for 10 buildings, none of the retrofits we evaluated meets the emissions limit. Increasing the payment alone does not solve their underlying emissions problem.

  So the broader takeaway is that financial incentives matter, but so does having effective retrofit options available.
]

// ---- 13: Monte Carlo -------------------------------------------------------

#s([Most retrofit recommendations are robust to uncertainty], stop: 5)[

  #let stability-bar(label, pct, color) = {
    grid(
      columns: (1fr, auto),
      align: horizon,
      text(size: 14pt)[#label],
      text(
        size: 25pt,
        weight: "bold",
        fill: color,
      )[#pct%],
    )
    v(5pt)
    box(width: 100%)[
      #rect(
        width: 100%,
        height: 24pt,
        radius: 2pt,
        fill: rgb("#eaeaea"),
        stroke: none,
      )
      #place(top + left)[
        #rect(
          width: pct / 100 * 100%,
          height: 24pt,
          radius: 2pt,
          fill: color,
          stroke: none,
        )
      ]
    ]
  }

  #grid(
    columns: (1fr, 1.5fr),
    column-gutter: 25pt,
    {
      text(size: 17pt, weight: "bold", fill: navy)[
        What if our assumptions change?
      ]
      v(8pt)

      set text(size: 14.5pt)
      list(
        [Installation costs],
        [Future energy prices],
        [Discount rates],
        [Retrofit performance],
      )

      v(12pt)
      text(size: 36pt, weight: "bold", fill: navy)[5,000]
      linebreak()
      text(size: 15pt)[Monte Carlo draws per office]

      v(8pt)
      text(size: 12pt, fill: ink-2)[
        Recalculate the cheapest option under different combinations of assumptions.
      ]
    },
    {
      text(size: 17pt, weight: "bold", fill: navy)[
        How often does the recommendation remain cheapest?
      ]

      v(12pt)
      stability-bar([Owner's perspective], 75.0, c-blue)

      v(12pt)
      stability-bar([Society's perspective], 80.2, green-edge)

      v(6pt)
      text(size: 11pt, fill: muted)[
        Average recommendation stability across 81 offices under projected conditions.
      ]

      v(6pt)
      text(size: 13pt)[
        Stability is below 50% for 12 offices (owner) and 7 offices (society).
      ]
    },
  )

  #v(1fr)
  #takeaway[
    Our recommendations are generally robust, but some buildings require closer individual evaluation.
  ]
]
#speaker-note[
  [??] Of course, our recommendations depend on assumptions about the future, and those assumptions come with uncertainty.

  To account for this, we conducted a Monte Carlo analysis with 5,000 draws per office, varying installation costs, energy prices, discount rates, and estimated retrofit performance.

  For each draw, we recalculate the costs and identify the cheapest option. We then measure how often our original recommendation remains the cheapest.

  On average, the original recommendation remains optimal in 75 percent of draws from the owner's perspective and 80 percent from society's perspective.

  However, there are buildings where the original recommendation remains optimal less than half the time. Our results are therefore generally robust, but some buildings would benefit from a more detailed individual assessment before making an investment decision.
]

// ---- 14. Conclusion --------------------------------------------------------

#s([Data-driven retrofit recommendations can guide policy], stop: 5)[

  #let point(title, body) = {
    text(size: 15pt, weight: "bold", fill: navy)[#title]
    v(3pt)
    text(size: 14pt)[#body]
    v(8pt)
  }

  #grid(
    columns: (1fr, 1fr),
    column-gutter: 25pt,
    {
      text(size: 17pt, weight: "bold", fill: green-edge)[
        What we learned
      ]
      v(10pt)
      point(
        [Data science adds value],
        [Matching similar buildings measurably improves retrofit predictions in our validation.],
      )
      point(
        [Decarbonization can pay off],
        [Retrofits offer substantial long-term financial and societal savings.],
      )
      point(
        [Incentives matter],
        [Private financial interests do not always align with societal interests.],
      )
    },
    {
      text(size: 17pt, weight: "bold", fill: navy)[
        Limitations and future work
      ]
      v(10pt)
      point(
        [Real-world validation],
        [Validate predictions against observed retrofit outcomes.],
      )
      point(
        [Building compatibility],
        [Improve matching for buildings with unusual fuel mixes and expand available retrofit options.],
      )
      point(
        [Broader applicability],
        [Extend the framework beyond offices and incorporate budget and scheduling constraints.],
      )
    },
  )
  #v(1fr)
  #takeaway[
    Our framework turns building data into actionable decarbonization investment decisions.
  ]
]
#speaker-note[
  [KT] To conclude, our results demonstrate how data science can support practical decarbonization decisions.

  We've shown that matching similar buildings improves our retrofit predictions, that reducing emissions can generate substantial long-term savings, and that existing financial incentives do not always align the interests of building owners with those of society.

  However, our framework has limitations. Real-world validation remains our priority, alongside improving building compatibility, expanding our retrofit options, and incorporating investment constraints.

  Ultimately, our data science challenge was estimating retrofit impacts on real buildings using simulated data. Our domain challenge was identifying investments that balance costs and BERDO compliance.

  By connecting the two, we've developed a framework that turns data into practical decarbonization decisions.
]

// ---- Bublik & Sweet P -----------------------------------------------------------------

#slide({
  set align(center + horizon)
  text(size: 26pt, weight: "bold", fill: navy)[Team support]
  v(6pt)
  grid(
    columns: (auto, auto),
    column-gutter: 18pt,
    row-gutter: 8pt,
    image("img/bublik.jpg", height: 9cm), image("img/sweet-p.jpg", height: 9cm),
    text(size: 20pt, fill: navy)[*Mr. Bublik*, the 4th teammate],
    text(size: 20pt, fill: navy)[*Sweet P*, the newest addition],
  )
})
#speaker-note[
  [Battle it out]
]

// ---- references ------------------------------------------------------------

#s([References])[
  #set text(size: 8.5pt)
  #set par(justify: false)
  #columns(2, gutter: 20pt, bibliography("refs.yml", title: none, style: "ieee"))
]
