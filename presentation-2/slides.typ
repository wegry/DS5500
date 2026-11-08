// DS5500 Presentation 2: ACP vs. retrofit for Boston offices under BERDO.
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
#let scen = csv("data/scenarios.csv", row-type: dictionary)
#let case = csv("data/case_study.csv", row-type: dictionary)
#let breakeven = csv("data/breakeven.csv", row-type: dictionary).map(r => float(r.breakeven_acp_usd_per_t))
#let standards = csv("../dbt/seeds/berdo_emissions_standards.csv", row-type: dictionary).filter(r => (
  r.building_use == "Office"
))
// k-sensitivity of the cheapest compliant pick, with 5-year energy bills (dbt/financial_k_sensitivity.py).
// report/data/financial_k_summary.csv is an older run without energy costs; don't use it here.
#let ksens = csv("../dbt/analysis_outputs/financial_k_summary.csv", row-type: dictionary)
// leave-one-out validation of the matching on ComStock offices (dbt/loo_validation.py)
#let loo = csv("../dbt/analysis_outputs/loo_k_summary.csv", row-type: dictionary)
#let lootest = csv("../dbt/analysis_outputs/loo_tests.csv", row-type: dictionary)
// Farnsworth's options over 2030-2034 (undiscounted 5-year screen)
#let farn = csv("data/farnsworth_options.csv", row-type: dictionary)
#let case-row(id) = case.find(r => r.upgrade_id == str(id))
#let farn-row(id) = farn.find(r => r.upgrade_id == str(id))

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
  footer: text(fill: muted)[DS5500 · Presentation 2 · Theodoropoulos, Wegrzyniak, Lysytsyna],
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
  text(size: 13pt, fill: muted, tracking: 1pt)[DS5500 CAPSTONE · PRESENTATION 2 · TEAM 7]
  v(10pt)
  text(size: 38pt, weight: "bold", fill: navy)[Pay Boston or retrofit older buildings?]
  v(18pt)
  grid(
    columns: (auto, 1fr),
    column-gutter: 16pt,
    row-gutter: 14pt,
    text(size: 14pt, weight: "bold", fill: navy, tracking: 0.5pt)[DOMAIN \ PROBLEM],
    text(size: 19pt)[How can Boston office owners meet BERDO's emissions limits at the lowest cost?],

    text(size: 14pt, weight: "bold", fill: green-edge, tracking: 0.5pt)[DATA SCIENCE \ PROBLEM],
    text(size: 19pt)[How do we estimate what a retrofit does to a real building when nobody has measured it?],
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
        caption: [The 13 retrofits compared, from ComStock @comstock.],
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


// ---- 4. three datasets, no shared key ---------------------------------------

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

#s([Three datasets, three different grains, no shared key], stop: 2)[
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

#s([How we estimate an unobserved retrofit outcome], stop: 2)[
  #set text(size: 15pt)
  #figure(
    diagram(
      spacing: (10pt, 10pt),
      edge-stroke: 1pt + navy,
      mnode((0, 0), [① Real office], [from BERDO], <b>, fill: green-box),
      mnode((1, 0), [② Same type], [simulated offices only], <f>),
      mnode((2, 0), [③ Most similar], [size, energy use per ft², fuel mix], <d>),
      mnode((3, 0), [④ Keep 10], [pool their % change by fuel], <k>),
      mnode((4, 0), [⑤ Apply], [to the real building's own emissions], <r>, fill: green-box),
      edge(<b>, <f>, "-|>"),
      edge(<f>, <d>, "-|>"),
      edge(<d>, <k>, "-|>"),
      edge(<k>, <r>, "-|>"),
    ),
    caption: [Matching each real building to its 10 most similar simulated buildings (k-nearest neighbors). Read left to right.],
  )
  #v(2pt)
  #grid(
    columns: (auto, 1fr),
    column-gutter: 18pt,
    row-gutter: 12pt,
    align: (left + horizon, left + horizon),
    text(size: 13pt, weight: "bold", fill: green-edge)[MATCH],
    text(size: 16pt)[$
      d(b,c) = underbrace(abs(ln A_b/A_c), "size") + underbrace(abs(ln "EUI"_b/"EUI"_c), "energy per ft²") + underbrace(1/2 sum_f abs(s_(b,f) - s_(c,f)), "fuel mix")
    $],

    text(size: 13pt, weight: "bold", fill: green-edge)[PREDICT],
    text(size: 16pt)[$
      hat(G)_b = sum_f G_(b,f) dot r_f, quad r_f = (sum_(c in N_b) U_(c,f)) / (sum_(c in N_b) B_(c,f))
    $],
  )
  #align(center, text(
    size: 12.5pt,
    fill: ink-2,
  )[$b$ = real building, $c$ = simulated one, $A$ = building area, $N_b$ = its 10 matches. $G_(b,f)$ = reported emissions from fuel $f$; $U$, $B$ = simulated use after / before the upgrade. Logs make "twice as big" count the same at any size.])
  #v(1fr)
  #takeaway[We keep each building's *real* emissions and borrow only the *% change* from its simulated neighbors.]
]
#speaker-note[
  [KL] Here's how we make those predictions. We match each real BERDO office to simulated ComStock offices that look similar in size, energy use per square foot, and fuel mix. We keep the ten closest. Then we look at how an upgrade changes energy use in those simulations.For example, heat pumps might reduce gas use but increase electricity use. We combine the change for each fuel across the matches, taking account of how much of that fuel they used before the upgrade. Then we apply those changes to the real building's reported emissions. So we're not copying a simulated building's final result. We're borrowing the estimated change to predict what might happen to the real building.
]

// ---- 6. sensitivity to k ----------------------------------------------------

#s([Ten neighbors predict hidden buildings better than no matching], stop: 2)[
  #let num = loo.filter(r => r.k not in ("all", "type"))
  #let ks = num.map(r => int(r.k))
  #let mae = num.map(r => float(r.mae_pp))
  #let kmax = ks.last()  // floor(sqrt(number of office models)), set in loo_validation.py
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
        ylim: (4.9, 6.6),
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
        lq.plot((10,), (at("10"),), stroke: none, mark: "o", mark-size: 9pt, color: c-blue),
        lq.place(10, at("10"), align: top + center, pad(top: 9pt, text(
          size: 11.5pt,
          weight: "bold",
          fill: c-blue,
        )[$k = 10$: #at("10")])),
      )),
      caption: [Leave-one-out test on #loo.at(0).held_out_models simulated Boston offices: hide one, predict its emissions cut for each of the eight retrofits from its $k$ nearest others ($k$ = 1 to √#loo.at(0).held_out_models ≈ #ks.last()), compare with ComStock's result.],
    ),
    {
      set text(size: 14.5pt)
      v(10pt)
      list(
        [$k = 10$ is off by *#at("10")* pct-pts on average, vs. *#at("all")* with no matching: #calc.abs(float(t-all.mean_diff_pp)) better (95% CI #calc.abs(float(t-all.ci95_high_pp))–#calc.abs(float(t-all.ci95_low_pp)), paired bootstrap).],
        [One neighbor is *worse* than no matching. Error is flat from $k approx 6$ up to $sqrt(n) approx #kmax$.],
        [Picks are stable too: #calc.round(stab9)% change between $k = 9$ and 10, mostly near-ties.],
      )
    },
  )
  #v(6pt)
  #takeaway[Matching measurably helps. But this is error *between simulations*, not against real retrofits.]
]
#speaker-note[
  [ZW] We can't check our predictions against real retrofits, because they haven't happened. But ComStock's simulated buildings do have a known answer. So we hid each of the 618 simulated Boston offices in turn, treated it like a real building, matched it to its k nearest other simulated offices with exactly the same distance we use for BERDO, and predicted its emissions cut for each of the eight retrofits. Then we compared against what ComStock actually simulated for it.

  The line is the average error in percentage points of emissions cut. With ten neighbors we're off by about 5.3 points. If we didn't match at all and just pooled every other office, we'd be off by about 6.1. Using only small, medium or large office gets 5.7. The improvement from matching is about 0.85 points, and a paired bootstrap over buildings puts the 95 percent interval at 0.5 to 1.2, so it's not noise. One neighbor is actually worse than not matching, and the curve is flat from about 6 up to 24, the square root of the number of buildings, which is the usual rule-of-thumb ceiling for k. So ten is a reasonable choice, not a tuned one.

  The hardest case is the heat-pump packages: about 10 points of error on an average cut of 18 percent. So treat individual heat-pump estimates as rough.

  Picks are also stable: between k equals 9 and 10, about 21 percent of recommendations change, and keeping the k-10 pick costs a median of under three thousand dollars over five years. If asked why: 5 of those 15 changes are swaps between Package 2 and Package 4, which are the same retrofit, LED plus heat pumps, and differ only in the efficiency of the rooftop heat pump. Both replace boilers with the same heat-pump boiler, so for buildings whose neighbors have no rooftop units, 138 of our 297, ComStock gives them identical results. BERDO doesn't record HVAC system type, so we can't tell which one fits a real building.

  The caveat: this measures how well neighbors transfer between simulated buildings. Real buildings can differ from every simulation in ways size, energy use and fuel mix don't capture.
]

// ---- 7. the five-year decision rule ----------------------------------------

#s([Per building: cheapest overall vs. cheapest under the limit], stop: 3)[
  #set text(size: 15pt)
  #grid(
    columns: (auto, 1fr),
    column-gutter: 20pt,
    row-gutter: 9pt,
    align: (left + horizon, left + horizon),
    text(size: 13pt, weight: "bold", fill: navy)[OPTIONS],
    [No upgrade (pay the ACP) · 7 single measures · 6 packages = *up to 14 per building*],

    text(size: 13pt, weight: "bold", fill: navy)[ENERGY / YR],
    text(size: 16pt)[$ E = sum_f "kWh"_(b,f) dot r_f dot "price"_f $],

    text(size: 13pt, weight: "bold", fill: navy)[ACP / YR],
    text(size: 16pt)[$ "ACP" = \$234 times max(0, hat(G)_b - 3.2 dot A_b) $],

    text(size: 13pt, weight: "bold", fill: navy)[5-YEAR COST],
    text(size: 16pt)[$ C_5 = C_"install" + 5 times (E + "ACP") $],
  )
  #v(4pt)
  #text(
    size: 13pt,
    fill: ink-2,
  )[2030–2034 is one BERDO period, so the limit and the ACP are constant. $hat(G)_b$ counts electricity at BERDO's projected 2030 factor @berdo-grid. No discounting. Prices: Massachusetts commercial averages @eia-prices @doer-oil. Install costs: BTB @btb.]
  #v(8pt)
  #grid(
    columns: (1fr, 1fr),
    column-gutter: 20pt,
    block(
      inset: 10pt,
      radius: 4pt,
      stroke: (left: 4pt + c-orange),
      [*Cheapest overall:* lowest $C_5$. May still be over the limit.],
    ),
    block(
      inset: 10pt,
      radius: 4pt,
      stroke: (left: 4pt + c-blue),
      [*Cheapest under the limit:* lowest $C_5$ with $hat(G)_b slash A_b <= 3.2$.],
    ),
  )
  #v(1fr)
  #takeaway[Install costs are benchmarks, not quotes. But *#stats.robust_to_cost of #stats.matched* buildings get the same pick at low, mid or high BTB prices.]
]
#speaker-note[
  [KT] Now that we can estimate the impact and cost of different retrofits, the next question is: which option should a building owner choose? For each building, we evaluate up to fourteen alternatives: doing nothing, seven individual upgrades, and six retrofit packages.

  We compare their total costs over the first five-year BERDO period, from 2030 to 2034. These costs include the upfront installation expense, energy bills, and any ACPs for emissions above the limit, with electricity counted the way BERDO will count it in 2030.

  We then report two outcomes: the cheapest option overall and the cheapest retrofit that actually brings the building under the limit.

  We also test how sensitive our recommendations are to installation costs, since these are estimates rather than actual contractor quotes.

  Across our 297 buildings, 207 receive the same recommendation under all three cost scenarios, suggesting that many of our results are relatively robust to uncertainty in installation costs.
]

// ---- 7b. Farnsworth, five years ---------------------------------------------
#s([Farnsworth: meeting the limit costs #thousands(case-row(55).delta_5yr_owner) more over five years], stop: 3)[
  #set text(size: 14pt)
  #let shown = (0, 48, 49, 43, 46, 65, 55, 56)
  #let label(id) = (
    "0": [No upgrade (pay ACP)],
    "48": [Wall insulation],
    "49": [Roof insulation],
    "43": [LED lighting],
    "46": [Rooftop PV],
    "65": [Pkg 12: PV + roof],
    "55": [Pkg 2 or 4: LED + heat pumps],
    "56": [Pkg 3: everything],
  ).at(str(id))
  #let hl(id) = if id == 0 { c-orange.lighten(80%) } else if id == 55 { c-blue.lighten(80%) } else { none }
  #figure(
    table(
      columns: (auto, auto, auto, auto, auto, auto, auto),
      align: (left, right, center, right, right, right, right),
      inset: (x: 9pt, y: 5pt),
      fill: (_, y) => if y > 0 { hl(shown.at(y - 1, default: -1)) },
      table.hline(stroke: 0.8pt),
      table.header([Option], [kg/ft²], [Meets 3.2?], [Install], [ACP, 5 yr], [Energy, 5 yr], [Total, 5 yr]),
      table.hline(stroke: 0.5pt),
      ..shown
        .map(id => {
          let r = farn-row(id)
          (
            label(id),
            str(calc.round(float(r.projected_ghg), digits: 2)),
            if r.meets_standard == "true" [*Yes*] else [No],
            thousands(r.installation_usd),
            thousands(r.acp_5yr_usd),
            thousands(r.energy_5yr_usd),
            strong(thousands(r.total_5yr_usd)),
          )
        })
        .flatten(),
      table.hline(stroke: 0.8pt),
    ),
    caption: [Five-year costs (2030–2034) for 24–32 Farnsworth St (BERDO 106476), mid prices. New windows and Package 1 cost \$2.7–2.8M and still miss the limit.],
  )
  #v(1fr)
  #takeaway[The cheapest move is to *do nothing and pay*. The cheapest retrofit under the limit is Package 2.]
]
#speaker-note[
  [KL] Here's Farnsworth's five-year result. The lowest-cost option is no upgrade, at about \$1.37 million, including energy bills and ACP payments. Packages 2 and 4 are tied as the cheapest retrofits that bring emissions below the standard, at about \$1.81 million. So reaching the emissions target costs roughly \$445,000 more over five years. Paying the ACP is an allowed way to meet BERDO obligations, but it doesn't bring the building's emissions below the target. That's the tradeoff we're seeing.
]

// ---- 8. the 20-year method, owner vs society --------------------------------

#s([Over 20 years: the owner's view and society's view], stop: 3)[
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
      [ACP on tons *over the limit*; grows as the limit steps down in 2035, 2040, 2045],
      [\$230 per ton on *every* ton (climate damage) @epa-scghg. ACP left out: it's a transfer to the city.],
      [Discount rate $r$], [7% (owner's cost of capital)], [2% (matches the carbon price)],
      table.hline(stroke: 0.8pt),
    ),
    caption: [EN 15459 global cost @en15459, as in the EU cost-optimal method @eu-cost-optimal. Equipment lifetimes from BTB @btb.],
  )
  #v(1fr)
  #takeaway[Baseline: the ACP follows *BERDO's projected grid factor*, as in the 5-year screen. *Energy prices, the ACP rate and the carbon price* stay at today's level.]
]
#speaker-note[
  [ZW] Five years undersells a retrofit that lasts twenty, so we also compute a 20-year cost. This is the European standard for comparing building upgrades, EN 15459. Equipment includes replacing anything that wears out inside 20 years, minus the value left at the end. Then every year's energy bill and emissions cost, discounted, because a dollar in 2045 is worth less than a dollar today.

  The owner pays the ACP only on tons over the limit, and that grows each time the limit steps down. The owner discounts at 7 percent. Society counts the climate damage of every ton at 230 dollars, the EPA's 2023 social cost of carbon, and leaves out the ACP because that's just money moving from the owner to the city. Society discounts at 2 percent.

  In the baseline, the owner's ACP follows BERDO's projected grid factor, and society's climate damage follows NLR's Cambium projections for the New England grid.
]

// ---- 9. answer: BERDO's grid factor and energy prices -------------------------

#s([Price forecasts barely matter. Boston's own grid factor does.], stop: 4)[
  // owner's view, one bar per scenario; the two decomposition scenarios go in the bullets
  #let shown = ("frozen", "projected", "lowogs", "highogs", "higheldmd")
  #let row(sc, p) = scen.find(r => r.scenario == sc and r.perspective == p)
  #let own = shown.map(sc => row(sc, "financial"))
  #let n = own.len()
  #let ys = range(n).rev()  // first scenario on top
  #let asc(arr) = arr.rev()
  #let col(rs, k) = rs.map(r => float(r.at(k)))
  #let u = col(own, "under_limit_anyway")
  #let a = col(own, "acp_only")
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
        [*#int(u.at(1))* of #stats.over_limit_today fall under the 2030 limit with *no retrofit*: BERDO's electricity factor drops 15% by 2030 as the RPS share rises from 27% to 40%.],
        [Of the rest, *#calc.min(..comp)–#calc.max(..comp)* pick a retrofit under the limit across AEO price cases (#int(g.at(0)) today). Prices alone: #int(row("prices_only", "financial").retrofit_compliant).],
        [Society: #soc("highogs")–#soc("lowogs") (#soc("frozen") today).],
      )
    },
  )
  #v(1fr)
  #takeaway[Projected prices don't change the answer. *BERDO's own falling grid factor does*: it's why #stats.over_limit offices, not #stats.over_limit_today, must pay or retrofit.]
]
#speaker-note[
  [KL] This slide shows how future electricity emissions and energy prices affect our retrofit decisions. Looking at the chart on the left, the top bar represents today’s conditions, where 65 buildings choose retrofits but still exceed the emissions limit, while 34 choose compliant retrofits. In the scenarios below, 18 buildings meet the limit without any retrofit, shown in green, mainly because BERDO projects a cleaner electricity grid by 2030. The orange and blue sections show that changing energy prices affects retrofit choices only slightly, with 22–27 buildings choosing compliant upgrades. So the main takeaway is that BERDO’s declining electricity emissions factor has a much bigger impact than future energy prices.

  If asked about price spikes: EIA's outlook draws smooth long-run paths; it doesn't model spikes. Recent high prices are in our starting point, which uses 2025 Massachusetts prices and, in the high case, 2026 gas prices. The closest thing to prices staying high is the low oil and gas supply case, where gas is 59 percent and electricity 24 percent higher by 2049. That's the "High prices" bar, and it moves the count by three.

  Caveats: the City reviews its factor projections at least every five years, and the renewable standard after 2030 is plus one percent a year unless the law changes. Cambium 2024 was built before 2025's federal policy changes, so its grid may be optimistic, but it only affects society's view.
]

// ---- 10. answer: the case --------------------------------------------------

#s([Back to Farnsworth: the cheapest choice can stay over the limit], stop: 4)[
  #let opts = ((65, [Package 12 (PV + roof)], c-orange), (55, [Package 2 (heat pumps)], c-blue))
  #let lenses = (
    ("delta_5yr_owner", [5 yr, owner]),
    ("delta_20yr_owner", [20 yr, owner]),
    ("delta_20yr_society", [20 yr, society]),
  )
  #let xs = range(lenses.len())
  #let swatch(c, t) = box(baseline: 1pt, rect(width: 11pt, height: 11pt, radius: 2pt, fill: c)) + h(4pt) + t
  #grid(
    columns: (1.35fr, 1fr),
    column-gutter: 20pt,
    figure(
      {
        align(center, text(size: 12.5pt, opts.map(((_, name, color)) => swatch(color, name)).join(h(18pt))))
        v(-2pt)
        chart(lq.diagram(
          width: 13cm,
          height: 6cm,
          xlim: (-0.6, 2.6),
          ylim: (-470, 560),
          ylabel: [Cost vs. just paying (\$ thousands)],
          xaxis: (ticks: xs.zip(lenses.map(l => l.at(1))), subticks: none),
          yaxis: (subticks: none, exponent: 0),
          // no grid: vertical gridlines would split each pair of bars down the middle
          grid: none,
          ..opts
            .enumerate()
            .map(((j, (id, name, color))) => {
              let vals = lenses.map(l => float(case-row(id).at(l.at(0))) / 1000)
              (
                lq.bar(xs, vals, offset: (j - 0.5) * 0.4, width: 0.38, fill: color, stroke: none),
                ..xs.map(i => lq.place(
                  i + (j - 0.5) * 0.4,
                  vals.at(i),
                  align: if vals.at(i) >= 0 { bottom } else { top },
                  pad(y: 3pt, text(size: 11pt, fill: ink)[#if vals.at(i) >= 0 [+]#calc.round(vals.at(i))k]),
                )),
              )
            })
            .flatten(),
          // zero line drawn after the bars so it reads as one continuous baseline
          lq.hlines(0, stroke: 1.2pt + ink),
          lq.place(0.62, 528, align: top + left, text(size: 11pt, fill: ink-2)[↑ costs more than paying]),
          lq.place(-0.55, -440, align: bottom + left, text(size: 11pt, fill: ink-2)[↓ cheaper than paying]),
        ))
      },
      caption: [24–32 Farnsworth St: each retrofit's cost minus the cost of just paying, at mid prices.],
    ),
    {
      set text(size: 14.5pt)
      v(10pt)
      list(
        [*5 yr, owner:* paying wins.],
        [*20 yr, owner:* Package 12 (rooftop PV + roof insulation) wins, but the building stays over the limit.],
        [*20 yr, society:* Package 2 wins and meets the limit.],
      )
    },
  )
  #v(12pt)
  #takeaway[*One building, three answers*, depending on the horizon and whose costs count.]
]
#speaker-note[
  [ZW] Farnsworth shows what this looks like for one building. Bars below zero are cheaper than just paying. Over five years, doing nothing is cheapest. Over 20 years, Package 12, rooftop solar plus roof insulation, becomes the owner's cheapest option, saving about 81 thousand dollars compared with paying, but it doesn't cut emissions enough to meet the limit. When we count society's costs, Package 2 wins, saving about 390 thousand dollars, and it meets the limit. So one building gets three different recommendations depending on the horizon and the objective.

  The owner's pick isn't fixed: with low gas prices, wall insulation edges out Package 12, and it stays over the limit either way. At today's grid, society would also pick Package 12; the cleaner projected grid is what tips it to heat pumps. Society here uses the social cost of carbon the EPA published in 2023. The EPA's current SCGG is \$0.
]

// ---- 11. answer: break-even ACP -------------------------------------------

#s([Today's ACP rarely makes meeting the limit the cheapest choice], stop: 5)[
  // Empirical CDF of the break-even ACP, counted out of all over-limit offices, so the
  // ones with no compliant retrofit show as the gap between the curve's top and the total.
  #let xmax = 3000
  #let be = breakeven.sorted()
  #let n-opt = be.len()
  #let shown = be.filter(v => v <= xmax)
  #let above = n-opt - shown.len()
  #let today = stats.acp_usd_per_t
  #let at-today = be.filter(v => v <= today).len()
  #let med = stats.breakeven_median
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
        ylabel: [Offices: retrofit under limit wins],
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
        )[↕ #(stats.over_limit - stats.with_compliant_option) offices: no retrofit gets under the limit]),
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
        [At today's *\$#today/t*, a retrofit under the limit beats the ACP for *#at-today* of #stats.over_limit.],
        [The median office with a retrofit under the limit tips at *\$#calc.round(med)/t*, about #calc.round(med / today, digits: 1)× today's rate.],
        [#(stats.over_limit - stats.with_compliant_option) offices never tip: none of our 13 retrofits meets the limit.],
      )
    },
  )
  #v(12pt)
  #takeaway[For most offices, today's ACP is too low for a retrofit under the limit to beat paying it.]
]
#speaker-note[
  [KT] Our results raise an interesting policy question: if paying the penalty is often cheaper than upgrading, how much would the payment need to increase before a retrofit under the limit beats paying it?

  To investigate this, we calculate the break-even payment over a 20-year horizon for buildings where our model identifies at least one retrofit that meets the emissions limit.

  The graph shows how many buildings would find a retrofit under the limit cheaper than the ACP as the payment increases.

  At today's rate of 234 dollars per ton, that's only 28 of the 81 buildings above the limit.

  For buildings with a retrofit under the limit, the median break-even rate is approximately 463 dollars per ton, about twice today's rate.

  But there's another important finding: none of the retrofits we evaluated gets 9 buildings under the limit. For those buildings, increasing the payment alone doesn't solve the underlying emissions problem.

  So the broader takeaway is that financial incentives matter, but so does having effective retrofit options available.

]

// ---- 12. next steps --------------------------------------------------------

#s([Next steps], stop: 5)[
  #set text(size: 16pt)
  #let step(n, title, body) = (
    text(size: 24pt, weight: "bold", fill: green-edge)[#n],
    text(size: 18pt, weight: "bold", fill: navy)[#title],
    body,
  )
  #grid(
    columns: (auto, 7.5cm, 1fr),
    column-gutter: 16pt,
    row-gutter: 32pt,
    align: (center + horizon, left + horizon, left + horizon),
    ..step(
      1,
      [Validate on real buildings],
      [The hold-out test checks simulations against simulations. Next: compare with engineering studies or post-upgrade BERDO data.],
    ),
    ..step(
      2,
      [Expand coverage],
      [More upgrades; fill BTB cost gaps so the #(stats.over_limit - stats.with_compliant_option) offices with no retrofit under the limit get one to test.],
    ),
    ..step(
      3,
      [Model time explicitly],
      [Let equipment costs change by year, and BERDO's grid factor change within each 5-year period, not just at its start.],
    ),
    ..step(4, [Constraints], [Plan *what* to retrofit and *when* under a budget.]),
  )
  #v(36pt)
  #takeaway[Our first priority is *confidence in the predicted outcomes*, not more financial complexity.]
]
#speaker-note[
  [KT] Looking ahead, we have four areas we'd like to improve.

  First, validation. We've tested our matching approach using simulated buildings, but we want to better understand how well it represents real-world applications.
  Second, we'd like to refine our cost estimates and expand our retrofit options, especially for buildings where none currently achieves compliance.
  Third, time-dependent assumptions. BERDO's projected grid factor reduces the number of offices above the limit from 99 to 81. But our model updates emissions every five years and holds equipment costs fixed. We'd like to model both annually.
  Finally, we'd like to introduce budget constraints to help determine not just which retrofits to choose, but when.

  To conclude, our data science challenge is estimating retrofit impacts on real buildings using simulated data.
  Our domain challenge is identifying investments that balance costs and BERDO compliance.
  Our goal is to connect the two, turning data into practical decarbonization decisions.
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
