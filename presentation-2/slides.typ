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
// Farnsworth's nine options over 2030-2034 (undiscounted 5-year screen)
#let farn = csv("../dbt/analysis_outputs/farnsworth_106476_options.csv", row-type: dictionary)
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
  text(size: 38pt, weight: "bold", fill: navy)[Pay Boston or fix up older buildings?]
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
  [KL] Our project is about a decision that many Boston building owners will have to make in the coming years: should they spend money upgrading their buildings, or is it cheaper to keep paying the city for excess emissions? We want to help owners choose the most cost-effective way to comply with Boston's emissions rules. And the cheapest option might not actually cut emissions enough to meet the standard.

  Before we can compare upgrades, we need to know what those upgrades would do to a building's energy and emissions. So our work is to estimate those outcomes first, and then use them to compare financial decisions.
]

// ---- 2. the decision in one slide ------------------------------------------

#s([#stats.over_limit of #stats.matched Boston offices must pay or fix by 2030], stop: 1)[
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
    },
    text(size: 24pt, fill: muted)[vs.],
    {
      text(size: 21pt, weight: "bold", fill: c-blue)[Fix]
      figure(
        table(
          columns: (auto, 1fr),
          align: (left, left),
          inset: (x: 6pt, y: 4pt),
          table.hline(stroke: 0.8pt),
          table.header([], [Retrofit]),
          table.hline(stroke: 0.5pt),
          [Single], [LED · wall insulation · roof insulation · windows],
          [Pkg 1], [Envelope: walls + roof + windows],
          [Pkg 2, 4], [LED + heat pumps (high / standard efficiency)],
          [Pkg 3], [Everything],
          table.hline(stroke: 0.8pt),
        ),
        caption: [The eight retrofits compared, from ComStock @comstock.],
      )
    },
  )
  #v(1fr)
  #takeaway[Fixing costs more up front and saves every year after. *So the answer depends on how far ahead you look.*]
]
#speaker-note[
  [KT] Why this matters. Boston has a regulation called BERDO, which limits how much greenhouse gas big buildings can emit. In our data we have 297 office buildings, and 99 are above the 2030 limit. Their owners have two main options.

  They can invest in retrofits, like better insulation, LED lighting, or heat pumps. Or they can pay an Alternative Compliance Payment, currently 234 dollars per ton over the limit, every year. And the limit keeps stepping down, so the payment grows. Retrofits are expensive up front; ACPs keep coming. So our domain question is: which option costs the least, and does that option actually bring the building under the limit?
]

// ---- 3. the example building -----------------------------------------------

#s([An example: 24 Farnsworth St], stop: 1)[
  #grid(
    columns: (auto, auto, 1fr),
    column-gutter: 16pt,
    figure(image(case-photo, height: 7.2cm), caption: [Photo: Boston Office Spaces @bos-listing.]),
    figure(image(case-map, height: 7.2cm), caption: [Fort Point, across the channel.]),
    {
      set text(size: 15pt)
      grid(
        columns: (auto, 1fr),
        row-gutter: 10pt,
        column-gutter: 12pt,
        [*Built*], [1915],
        [*Last renovated*], [1989],
        [*Floor area*], [#str(calc.round(stats.case_gfa_sqft / 1000)) k ft² @berdo],
        [*Energy*], [65% natural gas],
        [*Emissions*], [*#stats.case_intensity* kg CO#sub[2]e/ft²/yr],
      )
    },
  )
  #v(1fr)
  #takeaway[We have its current energy data, *not its response to a retrofit that hasn't happened.*]
]
#speaker-note[
  [ZW] As an example, we'll use one office building in Fort Point, 24 Farnsworth Street. It was built in 1915, last renovated in 1989, it's about 79 thousand square feet, and two thirds of its energy is natural gas. We know its reported energy use and emissions from BERDO. Now say the owner wants to install heat pumps or insulate the walls. How much would emissions drop? We don't know, because those retrofits haven't happened.
]

// ---- 4. the missing number -------------------------------------------------

#s([The missing data: what would this building emit after a retrofit?], stop: 2)[
  #let p2 = float(case-row(55).intensity)
  #let today = float(stats.case_intensity)
  #figure(
    chart(lq.diagram(
      width: 21cm,
      height: 4.6cm,
      xlim: (0, 5.6),
      ylim: (-0.6, 1.75),
      xlabel: [kg CO#sub[2]e / ft² / yr],
      yaxis: (
        ticks: (
          (0, [After Package 2 \ #text(fill: c-blue)[_estimated_]]),
          (1, [Today \ #text(fill: navy)[_measured_]]),
        ),
        subticks: none,
      ),
      xaxis: (subticks: none),
      grid: none,
      lq.hbar((today,), (1,), fill: navy, width: 0.55),
      lq.hbar(
        (p2,),
        (0,),
        fill: c-blue.lighten(45%),
        stroke: (paint: c-blue, thickness: 1.5pt, dash: "dashed"),
        width: 0.55,
      ),
      lq.vlines(3.2, stroke: (paint: c-orange, thickness: 2pt, dash: "dashed")),
      lq.place(3.2, 1.62, align: left, pad(left: 5pt, text(
        fill: c-orange.darken(10%),
        weight: "bold",
      )[2030 limit: 3.2 @berdo-standards])),
      lq.place(today, 1, align: left, pad(left: 5pt, text(weight: "bold")[4.80])),
      lq.place(p2, 0, align: left, pad(left: 5pt, text(weight: "bold", fill: c-blue)[2.39])),
    )),
    caption: [24 Farnsworth St. *Today*: reported to the city under BERDO @berdo. *After Package 2* (LED + heat pumps): our ComStock-based estimate @comstock, never observed.],
  )
  #v(1fr)
  #takeaway[Our data science target: *post-retrofit emissions for building × option*]
]
#speaker-note[
  [KL] This brings us to our data science problem. Farnsworth emits about 4.8 kilograms of CO2 per square foot, and the 2030 limit is 3.2. We want to know what happens to that 4.8 if the owner picks a particular upgrade. Our model predicts Package 2, LED lighting plus heat pumps, would bring it to 2.39, under the limit.

  But notice the difference. 4.8 is measured. 2.39 is estimated; that's why it's drawn dashed. Our data science task is to produce those estimates for every building and every retrofit. Without them we can't compute the remaining compliance payments or compare upgrades at all.
]

// ---- 5. three datasets, no shared key ---------------------------------------

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
  #v(1fr)
  #takeaway[Not a database join: *retrofit effects transfer by matching, costs by component mapping.*]
]
#speaker-note[
  [KT] So how do we estimate something that hasn't happened? We use three datasets. BERDO tells us about real Boston buildings: size, energy use, emissions. ComStock, from the National Lab of the Rockies, has simulated buildings and how their energy use changes after each retrofit. And BTB, the Buildings Technology Baseline, gives installation costs for the technologies in those retrofits.

  The catch is that these don't describe the same things. A real BERDO building has no ID in ComStock, and BTB describes technologies, not buildings. So instead of a join, we find comparable simulated buildings, transfer their retrofit effects, and price the components. The result is one row per real building and option, with projected emissions, install cost, energy bill and remaining compliance payment.
]

// ---- 6. matching ------------------------------------------------------------

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
  )[$b$ = real building, $c$ = simulated one, $N_b$ = its 10 matches. $G_(b,f)$ = reported emissions from fuel $f$; $U$, $B$ = simulated use after / before the upgrade. Logs make "twice as big" count the same at any size.])
  #v(1fr)
  #takeaway[We keep each building's *real* emissions and borrow only the *% change* from its simulated neighbors.]
]
#speaker-note[
  [KL] This is the main technical part of the project: k-nearest-neighbor matching. We take a real BERDO building, like Farnsworth, and compare it with simulated offices in ComStock on three things: size, energy use per square foot, and the share of energy from each fuel. Logs mean twice as big counts the same for a small or a huge building. We keep the ten closest.

  Then we look at what a given upgrade does to those ten. Say it cuts their gas use by 40 percent but raises electricity because of the heat pumps. We don't copy the simulated building's final emissions. We pool the percent change for each fuel across the ten, weighted by how much of that fuel they use, and apply it to Farnsworth's actual reported emissions. So we're using simulations to estimate how a real building would respond to a retrofit it has never had.
]

// ---- 7. sensitivity to k ----------------------------------------------------

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
        lq.place(kmax + 0.6, at("all"), align: bottom + right, pad(bottom: 2pt, text(size: 11pt, fill: ink-2)[No matching: all other offices])),
        lq.place(kmax + 0.6, at("type"), align: bottom + right, pad(bottom: 2pt, text(size: 11pt, fill: c-orange.darken(15%))[Office size class only])),
        lq.plot(ks, mae, stroke: 2pt + navy, mark: "o", mark-size: 4pt, color: navy),
        lq.plot((10,), (at("10"),), stroke: none, mark: "o", mark-size: 9pt, color: c-blue),
        lq.place(10, at("10"), align: top + center, pad(top: 9pt, text(size: 11.5pt, weight: "bold", fill: c-blue)[$k = 10$: #at("10")])),
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
  #v(1fr)
  #takeaway[Matching measurably helps. But this is error *between simulations*, not against real retrofits.]
]
#speaker-note[
  [ZW] We can't check our predictions against real retrofits, because they haven't happened. But ComStock's simulated buildings do have a known answer. So we hid each of the 618 simulated Boston offices in turn, treated it like a real building, matched it to its k nearest other simulated offices with exactly the same distance we use for BERDO, and predicted its emissions cut for each of the eight retrofits. Then we compared against what ComStock actually simulated for it.

  The line is the average error in percentage points of emissions cut. With ten neighbors we're off by about 5.3 points. If we didn't match at all and just pooled every other office, we'd be off by about 6.1. Using only small, medium or large office gets 5.7. The improvement from matching is about 0.85 points, and a paired bootstrap over buildings puts the 95 percent interval at 0.5 to 1.2, so it's not noise. One neighbor is actually worse than not matching, and the curve is flat from about 6 up to 24, the square root of the number of buildings, which is the usual rule-of-thumb ceiling for k. So ten is a reasonable choice, not a tuned one.

  The hardest case is the heat-pump packages: about 10 points of error on an average cut of 18 percent. So treat individual heat-pump estimates as rough.

  Picks are also stable: between k equals 9 and 10, 15 percent of recommendations change, and keeping the k-10 pick costs a median of under three thousand dollars over five years. If asked why: 8 of those 11 changes are swaps between Package 2 and Package 4, which are the same retrofit, LED plus heat pumps, and differ only in the efficiency of the rooftop heat pump. Both replace boilers with the same heat-pump boiler, so for buildings whose neighbors have no rooftop units, 138 of our 297, ComStock gives them identical results. BERDO doesn't record HVAC system type, so we can't tell which one fits a real building.

  The caveat: this measures how well neighbors transfer between simulated buildings. Real buildings can differ from every simulation in ways size, energy use and fuel mix don't capture.
]

// ---- 8. the five-year decision rule ----------------------------------------

#s([Per building: the cheapest option, and the cheapest that complies], stop: 3)[
  #set text(size: 15pt)
  #grid(
    columns: (auto, 1fr),
    column-gutter: 20pt,
    row-gutter: 9pt,
    align: (left + horizon, left + horizon),
    text(size: 13pt, weight: "bold", fill: navy)[OPTIONS],
    [No upgrade (pay the ACP) · 4 single measures · 4 packages = *9 per building*],

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
  )[2030–2034 is one BERDO period, so the limit and the ACP are constant. No discounting. Prices: Massachusetts commercial averages @eia-prices @doer-oil. Install costs: BTB @btb.]
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
      [*Cheapest compliant:* lowest $C_5$ with $hat(G)_b slash A_b <= 3.2$.],
    ),
  )
  #v(1fr)
  #takeaway[Install costs are benchmarks, not quotes. But *#stats.robust_to_cost of #stats.matched* buildings get the same pick at low, mid or high BTB prices.]
]
#speaker-note[
  [KT] Now the domain problem: choosing what to do. For each building we evaluate nine options: no upgrade, four single retrofits, and four packages. For the first five-year compliance period, 2030 to 2034, we add up installation cost, five years of energy bills, and five years of compliance payments. The limit doesn't change inside that period, so this is a simple sum, no discounting.

  We report two answers. The cheapest option overall, whether or not it meets the standard. And the cheapest option that actually gets under the limit.

  Equipment costs are national benchmarks, not contractor quotes, so we reran everything at BTB's low and high prices. 209 of 297 buildings get the same recommendation either way.
]

// ---- 9. Farnsworth, five years ----------------------------------------------

#s([At Farnsworth St, complying costs #thousands(case-row(55).delta_5yr_owner) more over five years], stop: 3)[
  #set text(size: 14pt)
  #let shown = (0, 48, 49, 43, 55, 56)
  #let label(id) = (
    "0": [No upgrade (pay ACP)],
    "48": [Wall insulation],
    "49": [Roof insulation],
    "43": [LED lighting],
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
            if r.meets_standard == "True" [*Yes*] else [No],
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
  #takeaway[The cheapest move is to *do nothing and pay*. The cheapest compliant one is Package 2.]
]
#speaker-note[
  [KL] Here's the model output for Farnsworth. Over five years, the cheapest option is doing nothing and paying the compliance charge: about 1.39 million dollars including energy bills. Notice energy is by far the biggest line for every option. The cheapest compliant options are Packages 2 and 4, about 1.81 million. So meeting the limit costs about 422 thousand dollars more over five years. That's the conflict: the owner minimizes cost with an option that doesn't meet the target.

  If asked why Packages 2 and 4 are identical here: Farnsworth's matched buildings have boilers, not rooftop units, so only the heat-pump boiler and LED parts of either package apply. The rooftop heat pump, the only part that differs, costs zero for this building.
]

// ---- 10. the 20-year method, owner vs society --------------------------------

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
  #takeaway[Held at today's level for all 20 years: *energy prices, grid emissions, the ACP rate and the carbon price.* Most of these favor paying.]
]
#speaker-note[
  [ZW] Five years undersells a retrofit that lasts twenty, so we also compute a 20-year cost. This is the European standard for comparing building upgrades, EN 15459. Equipment includes replacing anything that wears out inside 20 years, minus the value left at the end. Then every year's energy bill and emissions cost, discounted, because a dollar in 2045 is worth less than a dollar today.

  We look at it from two points of view. The owner pays the ACP only on tons over the limit, and that grows each time the limit steps down. The owner discounts at 7 percent. Society counts the climate damage of every ton at 230 dollars, the EPA's 2023 social cost of carbon, and leaves out the ACP because that's just money moving from the owner to the city. Society discounts at 2 percent.

  What we hold fixed: energy prices, the grid's emissions factor, the ACP rate and the carbon price, all at today's level. Most of that biases toward paying. Higher energy prices or a higher ACP would make retrofits look better. The grid getting cleaner is two-sided: it lowers emissions for heat pumps, but also for buildings that do nothing.
]

// ---- 11. answer: across the 99 ---------------------------------------------

#s([The cheapest option changes with the time horizon], stop: 4)[
  #let ys = range(outcomes.len()).rev()  // first scenario on top; lilaq sorts by y, so feed ascending
  #let asc(arr) = arr.rev()
  #let col(k) = outcomes.map(r => float(r.at(k)))
  #let a = col("acp_only")
  #let o = col("retrofit_over")
  #let g = col("retrofit_compliant")
  #let ao = a.zip(o).map(((x, y)) => x + y)
  #let swatch(c, t) = box(baseline: 1pt, rect(width: 11pt, height: 11pt, radius: 2pt, fill: c)) + h(4pt) + t
  #align(center, text(
    size: 13pt,
    swatch(c-gray, [Just pay])
      + h(18pt)
      + swatch(c-orange, [Retrofit, still over the limit])
      + h(18pt)
      + swatch(c-blue, [Retrofit that meets the 2030 limit]),
  ))
  #v(-4pt)
  #figure(
    chart(lq.diagram(
      width: 20cm,
      height: 5.2cm,
      xlim: (0, 99),
      ylim: (-0.6, 2.6),
      xlabel: [Over-limit office buildings (of #stats.over_limit)],
      yaxis: (ticks: range(outcomes.len()).zip(outcomes.map(r => r.scenario).rev()), subticks: none),
      xaxis: (ticks: (0, 25, 50, 75, 99), subticks: none),
      grid: none,
      lq.hbar(asc(a), asc(ys), fill: c-gray, stroke: 1.5pt + white, width: 0.62),
      // lilaq bars run from base to x, so x is the cumulative end
      lq.hbar(asc(ao), asc(ys), base: asc(a), fill: c-orange, stroke: 1.5pt + white, width: 0.62),
      lq.hbar(
        asc(ao.zip(g).map(((x, y)) => x + y)),
        asc(ys),
        base: asc(ao),
        fill: c-blue,
        stroke: 1.5pt + white,
        width: 0.62,
      ),
      ..range(outcomes.len())
        .map(i => {
          let parts = ((a.at(i), 0), (o.at(i), a.at(i)), (g.at(i), ao.at(i)))
          parts
            .filter(((n, b)) => n >= 3)
            .map(((n, b)) => lq.place(b + n / 2, ys.at(i), text(size: 13pt, weight: "bold", fill: white)[#int(n)]))
        })
        .flatten(),
    )),
    caption: [Cheapest option for each of the #stats.over_limit offices over the limit, at mid equipment prices.],
  )
  #v(1fr)
  #takeaway[Over 5 years, *#stats.over_acp_5yr of #stats.over_limit* owners should just pay. Over 20, nobody should, but only *#outcomes.at(1).retrofit_compliant* pick a fix that meets the limit.]
]
#speaker-note[
  [KL] Now all 99 buildings above the 2030 limit. Top bar, the five-year view: for 66 of them the cheapest move is to do nothing and pay, and only 3 have a compliant retrofit as their cheapest choice. Over 20 years retrofits look better, because there's more time to earn back the up-front cost. Nobody should only pay. But from the owner's point of view, only 24 buildings have a compliant retrofit as their cheapest option. Most pick something like wall insulation that saves money and stays over the limit.

  From society's point of view, where every ton is charged its climate cost and the future is discounted less, that rises to 35. So two things matter: the time horizon, and whose costs you count.
]

// ---- 12. answer: the case --------------------------------------------------

#s([Back to Farnsworth: the cheapest choice need not comply], stop: 4)[
  #let opts = ((48, [Wall insulation], c-orange), (55, [Package 2 (heat pumps)], c-blue))
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
          ylim: (-380, 560),
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
          lq.place(-0.55, -348, align: bottom + left, text(size: 11pt, fill: ink-2)[↓ cheaper than paying]),
        ))
      },
      caption: [24–32 Farnsworth St: each retrofit's cost minus the cost of just paying, at mid prices.],
    ),
    {
      set text(size: 14.5pt)
      v(10pt)
      list(
        [*5 yr, owner:* paying wins.],
        [*20 yr, owner:* wall insulation wins, but the building stays over the limit.],
        [*20 yr, society:* Package 2 wins and complies.],
      )
    },
  )
  #v(1fr)
  #takeaway[*One building, three answers*, depending on the horizon and whose costs count.]
]
#speaker-note[
  [ZW] Farnsworth shows what this looks like for one building. Bars below zero are cheaper than just paying. Over five years, doing nothing is cheapest. Over 20 years, wall insulation becomes the owner's cheapest option, saving about 80 thousand dollars compared with paying, but it doesn't cut emissions enough to meet the limit. When we count society's costs, Package 2 wins, saving about 303 thousand dollars, and it complies. So one building gets three different recommendations depending on the horizon and the objective.

  Keep in mind we hold energy prices and the grid at today's level for all 20 years. Society here uses the social cost of carbon the EPA published in 2023. The EPA's current SCGG is \$0.
]

// ---- 13. answer: break-even ACP -------------------------------------------

#s([Today's ACP rarely makes compliance the cheapest choice], stop: 5)[
  #let edges = (0, 234, 500, 1000, 2000, 1e9)
  #let labels = ([≤ \$234 \ (today)], [\$234–500], [\$500–1k], [\$1k–2k], [> \$2k])
  #let counts = range(5).map(i => breakeven
    .filter(v => v > edges.at(i) - (if i == 0 { 1 } else { 0 }) and v <= edges.at(i + 1))
    .len())
  #let xs = range(5)
  #grid(
    columns: (1.35fr, 1fr),
    column-gutter: 20pt,
    figure(
      chart(lq.diagram(
        width: 13cm,
        height: 5.4cm,
        ylim: (0, 29),
        ylabel: [Buildings],
        xlabel: [Break-even payment (\$ per ton)],
        xaxis: (ticks: xs.zip(labels), subticks: none),
        yaxis: (subticks: none),
        lq.bar(xs, counts, width: 0.7, stroke: 1.5pt + white, fill: counts
          .enumerate()
          .map(((i, _)) => if i == 0 { c-blue } else { c-gray })),
        ..xs.map(i => lq.place(i, counts.at(i), align: bottom, pad(bottom: 3pt, text(
          size: 12pt,
          weight: "bold",
        )[#counts.at(i)]))),
      )),
      caption: [ACP per ton at which a compliant retrofit becomes the owner's cheapest 20-year option (#stats.with_compliant_option offices with one).],
    ),
    {
      set text(size: 14.5pt)
      v(10pt)
      list(
        [Median: *\$#calc.round(stats.breakeven_median)/t*, about #calc.round(stats.breakeven_median / stats.acp_usd_per_t, digits: 1)× today's rate.],
        [*#stats.breakeven_le_current* already tip at \$234.],
        [#(stats.over_limit - stats.with_compliant_option) more have *no* retrofit among our eight that meets the limit.],
      )
    },
  )
  #v(1fr)
  #takeaway[Today's ACP is set below what it takes to make compliance the cheaper choice for most offices.]
]
#speaker-note[
  [KT] This raises a policy question. If it's often cheaper to stay over the limit, how high would the payment need to be before a compliant retrofit wins? For the 75 buildings where our model finds at least one compliant retrofit, we raised the payment until that happens.

  The median is about 571 dollars per ton, versus 234 today. Only 24 buildings tip at or below today's rate. And the other 24 of our 99 have no compliant option among the retrofits we evaluated, so raising the payment on them is just a tax unless deeper retrofits are on the table.
]

// ---- 14. next steps --------------------------------------------------------

#s([Next steps], stop: 5)[
  #set text(size: 16pt)
  #let step(n, title, body) = (
    text(size: 24pt, weight: "bold", fill: green-edge)[#n],
    text(size: 18pt, weight: "bold", fill: navy)[#title],
    body,
  )
  #grid(
    columns: (auto, 6.5cm, 1fr),
    column-gutter: 16pt,
    row-gutter: 20pt,
    align: (center + horizon, left + horizon, left + horizon),
    ..step(
      1,
      [Validate on real buildings],
      [The hold-out test checks simulations against simulations. Next: compare with engineering studies or post-upgrade BERDO data.],
    ),
    ..step(
      2,
      [Expand coverage],
      [More upgrades; fill BTB cost gaps so the 24 offices with no compliant option get one to test.],
    ),
    ..step(
      3,
      [Model time explicitly],
      [Let grid emissions @cambium, fuel prices and equipment costs change by year instead of holding them at today's level.],
    ),
    ..step(4, [Constraints], [Plan *what* to fix and *when* under a budget.]),
  )
  #v(1fr)
  #takeaway[Our first priority is *confidence in the predicted outcomes*, not more financial complexity.]
]
#speaker-note[
  [KT] Where we go next. First, validation on real buildings. The hold-out test showed matching works between simulated buildings, but not against real retrofits. Buildings that have already retrofitted will show up in later BERDO disclosures, and engineering studies give another check. Second, expand the options and fill gaps in the cost mapping. Third, model time explicitly: let grid emissions, fuel prices and costs change by year. Fourth, add a budget and plan what to fix and when. But our main priority is confidence in the predicted retrofit outcomes.

  To summarize: our domain problem is choosing the most cost-effective response to BERDO, and our data science problem is estimating the retrofit outcomes that decision needs. The cheapest option for an owner often isn't the one that meets the city's goals.
]

// ---- references ------------------------------------------------------------

#s([References])[
  #set text(size: 10pt)
  #set par(justify: false)
  #columns(2, gutter: 20pt, bibliography("refs.yml", title: none, style: "ieee"))
]

// ---- bonus -----------------------------------------------------------------

#slide({
  set align(center + horizon)
  text(size: 26pt, weight: "bold", fill: navy)[Bonus slide]
  v(6pt)
  image("img/bublik.jpg", height: 11cm)
  v(4pt)
  text(size: 22pt, fill: green-edge)[*Mr. Bublik*, the 4th teammate]
})
#speaker-note[
  [Battle it out]
]
