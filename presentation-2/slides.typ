// DS5500 Presentation 2: ACP vs. retrofit for Boston offices under BERDO.
//
// Build (from the repo root; --root lets the deck read dbt/seeds and report/data):
//   PDF : typst compile --root . presentation-2/slides.typ presentation-2/slides.pdf
//   PPTX: uvx --from touying touying compile --root . --format pptx \
//           presentation-2/slides.typ --output presentation-2/slides.pptx
// Refresh the numbers first with `uv run python presentation-2/make_data.py`.
//
// The PPTX holds one rendered image per slide plus the speaker notes, so edit here,
// not in PowerPoint.

#import "@preview/touying:0.7.4": *
#import themes.simple: *
#import "@preview/lilaq:0.6.0" as lq
#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node

// Optional photo for the opening slide, e.g. "img/farnsworth.jpg". Leave none to skip.
#let hero-photo = none
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
#let fuel = csv("../dbt/seeds/fuel_prices.csv", row-type: dictionary)
#let ksens = csv("../report/data/financial_k_summary.csv", row-type: dictionary)
#let case-row(id) = case.find(r => r.upgrade_id == str(id))

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

// The stops from the presentation plan; a strip at the top shows where we are.
#let stops = ([The problem], [Pay or fix], [Scoring], [Matching], [Results])

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

// ---- 0. title --------------------------------------------------------------

#slide({
  set align(horizon)
  grid(
    columns: if hero-photo == none { (1fr,) } else { (1.3fr, 1fr) },
    column-gutter: 24pt,
    {
      text(size: 13pt, fill: muted, tracking: 1pt)[DS5500 CAPSTONE · PRESENTATION 2 · NOVEMBER 2026]
      v(10pt)
      text(size: 38pt, weight: "bold", fill: navy)[Pay the #strike[fine] _payment_
        or fix the building?]
      v(4pt)
      text(
        size: 20pt,
        fill: ink-2,
      )[When is it cheaper for a Boston office to pay the city than to cut its emissions?]
      v(28pt)
      text(size: 16pt)[Konstantinos Theodoropoulos · Zachary Wegrzyniak · Kateryna Lysytsyna]
      linebreak()
      text(size: 13pt, fill: muted)[github.com/wegry/DS5500]
    },
    ..if hero-photo != none { (image(hero-photo, width: 100%),) },
  )
})
#speaker-note[
  Boston now limits how much carbon big buildings can put out. If your building goes over, you can pay the city or fix the building. We wanted to know which one is cheaper for Boston's offices. Short version: it depends a lot on how far out you look.
]

// ---- 2. the building --------------------------------------------------------

#s([24 Farnsworth St: built 1915, last renovated 1989], stop: 1)[
  #grid(
    columns: (auto, auto, 1fr),
    column-gutter: 16pt,
    figure(image(case-photo, height: 7.8cm), caption: [Photo: Boston Office Spaces @bos-listing.]),
    figure(image(case-map, height: 7.8cm), caption: [Fort Point, across the channel from downtown.]),
    {
      set text(size: 15pt)
      grid(
        columns: (auto, 1fr),
        row-gutter: 10pt,
        column-gutter: 12pt,
        [*Built*], [1915],
        [*Last renovated*], [1989],
        [*Stories*], [6],
        [*Floor area*], [#str(calc.round(stats.case_gfa_sqft / 1000)) k ft² @berdo],
        [*Energy*], [65% natural gas],
        [*Emissions*], [*#stats.case_intensity* kg/ft²/yr],
      )
    },
  )
  #v(1fr)
  #takeaway[Last renovated 37 years ago, and heated mostly with gas. *A typical Boston office with a typical problem.*]
]
#speaker-note[
  Meet 24 Farnsworth Street in Fort Point, right across the channel from South Station. It was built in 1915 and last renovated in 1989. Six stories, about 79 thousand square feet. Two thirds of its energy is natural gas. So it's old, it burns gas for heat, and it hasn't been touched in 37 years. That makes it a pretty good stand-in for a lot of Boston's office stock.
]

// ---- 3. motivation ---------------------------------------------------------

#let years-step(rows) = {
  // BERDO periods as a step function from 2025 to 2055
  let xs = rows.map(r => int(r.period_start)) + (2055,)
  let ys = rows.map(r => float(r.standard_kgco2e_sqft))
  (xs, ys + (ys.last(),))
}

#s([Boston caps building emissions. Farnsworth St is over.], stop: 1)[
  #text(size: 15pt)[*BERDO*, Boston's building emissions law @berdo, gives every large building a yearly CO#sub[2] limit per square foot. The limit steps down every five years until it hits zero in 2050.]
  #v(2pt)
  #let (xs, ys) = years-step(standards)
  #let p2 = float(case-row(55).intensity)
  #grid(
    columns: (1.25fr, 1fr),
    column-gutter: 22pt,
    figure(
      chart(lq.diagram(
        width: 12.5cm,
        height: 6.2cm,
        xlim: (2025, 2052),
        ylim: (0, 5.8),
        xlabel: [Year],
        ylabel: [kg CO#sub[2]e / ft² / yr],
        xaxis: (ticks: (2025, 2030, 2035, 2040, 2045, 2050), subticks: none),
        yaxis: (subticks: none),
        legend: (position: bottom + left, stroke: none, fill: white.transparentize(10%)),
        lq.plot(xs, ys, step: end, mark: none, stroke: 2pt + navy, label: [Boston's limit for offices]),
        lq.plot(
          (2025, 2052),
          (stats.case_intensity, stats.case_intensity),
          mark: none,
          stroke: (paint: c-orange, thickness: 2pt, dash: "dashed"),
          label: [Today, no retrofit (4.80)],
        ),
        lq.plot(
          (2030, 2052),
          (p2, p2),
          mark: none,
          stroke: (paint: c-blue, thickness: 2pt),
          label: [With heat-pump Package 2 (2.39)],
        ),
      )),
      caption: [BERDO limit for offices @berdo-standards vs. 24–32 Farnsworth St, Fort Point.],
    ),
    {
      set text(size: 15pt)
      v(10pt)
      list(
        [Puts out *#stats.case_intensity*. The 2030 limit is *3.2*.],
        [New LED lights + heat pumps: *2.39*.],
        [That costs #thousands(case-row(55).installed_cost_mid_usd). Or pay the city about \$30k a year.],
      )
    },
  )
  #v(1fr)
  #takeaway[One upgrade gets this building compliant for a decade. *Is it worth it, or should the owner just pay?*]
]
#speaker-note[
  Boston's law is called BERDO. Every big building gets a carbon limit per square foot, and the dark line shows it stepping down to zero by 2050. Farnsworth Street puts out 4.8 kilos per square foot a year, and in 2030 the limit drops to 3.2. So it's over. But it's not hopeless. The blue line is LED lighting plus heat pumps, and that puts it under the line until 2040. Install cost is about seven hundred thousand. The alternative is writing the city a check for about thirty thousand a year. That's the whole project in one building.
]

// ---- 3. the decision -------------------------------------------------------

#s([#stats.over_limit of #stats.matched Boston offices must pay or fix by 2030], stop: 2)[
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
      text(fill: ink-2)[Cheap now. Grows as the limit drops every five years.]
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
          [Pkg 2, 4], [LED + heat pumps],
          [Pkg 3], [Everything],
          table.hline(stroke: 0.8pt),
        ),
        caption: [The eight retrofits compared.],
      )
    },
  )
  #v(1fr)
  #takeaway[Fixing costs more up front and saves every year after. *So the answer depends on how far ahead you look.*]
]
#speaker-note[
  We look at Boston's offices, because they report the most complete data. That's 297 buildings, and 99 of them are over the 2030 limit. Those 99 have two kinds of choices. Pay the city 234 dollars for every ton they're over, every year. That's called an Alternative Compliance Payment, or ACP. Or fix the building with one of eight retrofits, from LED bulbs up to the whole works. Paying is cheap now and gets worse every five years. So it's a timing question.
]

// ---- 4. formula -------------------------------------------------------------

#s([We compare options by their total cost over 20 years], stop: 3)[
  #set text(size: 15pt)
  #align(center, block(inset: 8pt, radius: 6pt, stroke: 0.6pt + rule, text(size: 16pt)[
    $
      "Cost" = underbrace(C_"equipment", "install + replace" \ "when worn out")
      + sum_(t=1)^(20) (overbrace(E_t, "energy bills" \ "in year" t) + overbrace(P_t, "emissions cost" \ "in year" t)) / underbrace((1+r)^t, "future dollars" \ "count less")
    $
  ]))
  #v(10pt)
  #figure(
    table(
      columns: (auto, 1fr, 1fr),
      align: (left, left, left),
      inset: (x: 8pt, y: 3pt),
      table.hline(stroke: 0.8pt),
      table.header([], [Owner's view], [Society's view]),
      table.hline(stroke: 0.5pt),
      [Emissions cost $P_t$], [ACP on tons *over the limit*], [\$230 per ton on *every* ton (climate damage) @epa-scghg],
      [Discount rate $r$], [7% (future dollars worth less)], [2%],
      table.hline(stroke: 0.8pt),
    ),
    caption: [Two points of view on the same building. Formula: EN 15459 global cost @en15459 @eu-cost-optimal. Equipment: NLR Buildings Technology Baseline @btb. Energy: Massachusetts prices @eia-prices @doer-oil.],
  )
  #v(1fr)
  #takeaway[Equipment prices are benchmarks, not quotes. But *#stats.robust_to_cost of #stats.matched* buildings get the same pick at low, mid or high prices.]
]
#speaker-note[
  How do you compare a one-time install against a check every year? Add everything up over 20 years: equipment, including replacing what wears out; energy bills, so heat pumps pay for pricier electricity; and an emissions cost. Then we look at it two ways. The owner pays the ACP on tons over the limit, and cares a lot about money now. Society counts climate damage on every ton and is more patient. The formula isn't ours. It's EN 15459, the European standard for comparing building upgrades. Equipment prices are benchmarks, but for 209 of 297 buildings the answer holds at low or high prices.
]

// ---- 5. matching ------------------------------------------------------------

#let mnode(pos, title, detail, name, fill: white) = node(
  pos,
  align(center)[#text(size: 13pt, weight: "bold")[#title] \ #text(size: 11.5pt, fill: ink-2)[#detail]],
  name: name,
  width: 4.4cm,
  height: 2.2cm,
  inset: 5pt,
  corner-radius: 4pt,
  stroke: 0.8pt + navy,
  fill: fill,
)

#s([Real buildings borrow retrofit results from similar simulated ones], stop: 4)[
  #set text(size: 15pt)
  #grid(
    columns: (1fr, 1fr), column-gutter: 24pt,
    [*BERDO* @berdo has real buildings, but nothing on what a retrofit would do to them.],
    [*ComStock* @comstock, from a national lab, simulates retrofits, but only on made-up buildings.],
  )
  #v(6pt)
  #figure(
    diagram(
      spacing: (10pt, 10pt),
      edge-stroke: 1pt + navy,
      mnode((0, 0), [① Real office], [from BERDO], <b>, fill: green-box),
      mnode((1, 0), [② Same type], [simulated offices only], <f>),
      mnode((2, 0), [③ Most similar], [size, energy use per ft², fuel mix], <d>),
      mnode((3, 0), [④ Keep 10], [average their savings], <k>),
      mnode((4, 0), [⑤ Apply], [those % savings to the real building], <r>, fill: green-box),
      edge(<b>, <f>, "-|>"),
      edge(<f>, <d>, "-|>"),
      edge(<d>, <k>, "-|>"),
      edge(<k>, <r>, "-|>"),
    ),
    caption: [Matching each real building to its 10 most similar simulated buildings (k-nearest neighbors). Read left to right.],
  )
  #v(4pt)
  #align(center, text(size: 17pt)[
    $ "distance"(b,c) = underbrace(abs(ln A_b/A_c), "size") + underbrace(abs(ln "EUI"_b/"EUI"_c), "energy use per ft²") + underbrace(1/2 sum_f abs(s_(b,f) - s_(c,f)), "fuel mix") $
  ])
  #align(center, text(size: 13pt, fill: ink-2)[$b$ = real building, $c$ = simulated one. Logs make "twice as big" count the same for a small or a huge building.])
  #v(1fr)
  #takeaway[*Why 10:* with one match, #calc.round(float(ksens.at(0).different_recommendations) / float(ksens.at(0).compliant_buildings_compared) * 100)% of recommendations change. With nine, only #calc.round(float(ksens.at(8).different_recommendations) / float(ksens.at(8).compliant_buildings_compared) * 100)% do.]
]
#speaker-note[
  Here's the data problem. BERDO has real buildings but no idea what a heat pump would do for them. ComStock, from a national lab, knows exactly what a heat pump does, but only for simulated buildings. So we match. For each real office, we look at simulated offices, find the ten most similar by size, energy use per square foot, and fuel mix, and borrow their percent savings. Why ten? With one match, a third of the recommendations flip. With nine, it's one in twenty.
]

// ---- 9. answer: across the 99 ---------------------------------------------

#s([Over 5 years, paying wins. Over 20, retrofitting does.], stop: 5)[
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
    caption: [Cheapest 20-year option for each of the #stats.over_limit offices over the limit, at mid prices.],
  )
  #v(1fr)
  #takeaway[Over 5 years, *#stats.over_acp_5yr of #stats.over_limit* owners should just pay. Over 20, nobody should, but only *#outcomes.at(1).retrofit_compliant* pick a fix that actually meets the limit.]
]
#speaker-note[
  Here's the answer across all 99 offices that are over the limit. Top bar, the five-year view: for 66 of them the cheapest move is to just pay the ACP. Middle bar, same owners looking out 20 years: nobody should only pay. Energy savings add up. But look at the orange. Most owners' cheapest retrofit is something like wall insulation, which saves money and still leaves them over the limit. Only 24 land on a fix that gets them compliant. Bottom bar, society's view, gets you to 35.
]

// ---- 10. answer: the case --------------------------------------------------

#s([Back at Farnsworth St: the owner and the city disagree], stop: 5)[
  #let opts = ((48, [Wall insulation], c-orange), (55, [Package 2 (heat pumps)], c-blue))
  #let lenses = (
    ("delta_5yr_owner", [5 yr, owner]),
    ("delta_20yr_owner", [20 yr, owner]),
    ("delta_20yr_society", [20 yr, society]),
  )
  #let xs = range(lenses.len())
  #grid(
    columns: (1.35fr, 1fr),
    column-gutter: 20pt,
    figure(
      chart(lq.diagram(
        width: 13cm,
        height: 6.4cm,
        ylim: (-380, 500),
        ylabel: [Cost vs. just paying (\$ thousands)],
        xaxis: (ticks: xs.zip(lenses.map(l => l.at(1))), subticks: none),
        yaxis: (subticks: none, exponent: 0),
        legend: (position: top + right, stroke: none),
        lq.hlines(0, stroke: 1pt + ink-2),
        ..opts
          .enumerate()
          .map(((j, (id, name, color))) => {
            let vals = lenses.map(l => float(case-row(id).at(l.at(0))) / 1000)
            (
              lq.bar(xs, vals, offset: (j - 0.5) * 0.36, width: 0.34, fill: color, stroke: 1.5pt + white, label: name),
              ..xs.map(i => lq.place(
                i + (j - 0.5) * 0.36,
                vals.at(i),
                align: if vals.at(i) >= 0 { bottom } else { top },
                pad(y: 3pt, text(size: 11pt, fill: ink)[#if vals.at(i) >= 0 [+]#calc.round(vals.at(i))k]),
              )),
            )
          })
          .flatten(),
      )),
      caption: [24–32 Farnsworth St: each retrofit's cost minus the cost of just paying. Below zero means cheaper than paying.],
    ),
    {
      set text(size: 14.5pt)
      list(
        [*5 yr:* paying wins.],
        [*20 yr, owner:* wall insulation wins, but stays over the limit.],
        [*20 yr, society:* Package 2 wins.],
      )
    },
  )
  #v(1fr)
  #takeaway[At \$234/t the owner's cheapest move leaves the building over the limit. Society's cheapest move gets it compliant.]
]
#speaker-note[
  Back to Farnsworth Street. Bars below zero are cheaper than just paying. Over five years, paying wins, Package 2 is four hundred grand worse. Over twenty, the owner's best bet is wall insulation: saves about eighty grand, and the building is still over the limit every single year. From society's side, counting the climate damage of every ton, Package 2 wins by three hundred thousand. So the owner and the city want different things here, and the ACP is what's supposed to close that gap.
]

// ---- 11. answer: break-even ACP -------------------------------------------

#s([The payment would need to be about 2.4× higher to tip the typical building], stop: 5)[
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
      caption: [Payment per ton at which a retrofit that meets the limit becomes the owner's cheapest option (#stats.with_compliant_option offices).],
    ),
    {
      set text(size: 14.5pt)
      list(
        [Median: *\$#calc.round(stats.breakeven_median)/t*.],
        [*#stats.breakeven_le_current* already tip at \$234.],
        [#(stats.over_limit - stats.with_compliant_option) more have *no* retrofit that meets the limit.],
      )
    },
  )
  #v(1fr)
  #takeaway[Today's ACP is set below what it takes to make compliance the cheaper choice for most offices.]
]
#speaker-note[
  So how high would the payment need to be? For every building we raise the payment until a retrofit that meets the limit becomes the cheapest option. The blue bar is the 24 that already tip at 234. The median is about 570 dollars a ton, so roughly two and a half times today's rate. And 24 buildings have no compliant option in our eight at all. Raising the ACP on them is just a tax unless deeper retrofits are on the table.
]

// ---- 12. discussion --------------------------------------------------------

#s([Discussion])[
  #set text(size: 18pt)
  #grid(
    columns: (1fr, 1fr),
    column-gutter: 28pt,
    {
      text(size: 19pt, weight: "bold", fill: navy)[What it means]
      list(
        [*When* you look decides the answer.],
        [The cheapest fix usually isn't compliant.],
        [\$234/t is about 40% of what tips the typical office.],
      )
    },
    {
      text(size: 19pt, weight: "bold", fill: c-orange.darken(15%))[What we don't trust yet]
      list(
        [Wall insulation wins too often. Checking its cost.],
        [Energy prices and grid held at today's levels.],
        [Not yet compared with ranking fixes by cost per ton.],
      )
    },
  )
  #v(1fr)
  #takeaway[*Next:* compare with cost-per-ton ranking, add a cleaner-grid forecast @cambium, then plan *what* to fix and *when* under a budget.]
]
#speaker-note[
  So what does it mean? First, when you look decides the answer. A five-year budget says pay, a twenty-year plan says retrofit. Second, cheapest isn't compliant. And the ACP is about 40 percent of what it'd need to be to change that for a typical office. What I don't trust yet: wall insulation wins way too often, so we're checking whether its cost data is too low. Prices and the grid are frozen at today's levels, and the grid is getting cleaner. And the usual way people pick retrofits is ranking them by cost per ton. We haven't compared against that yet. That's next. Thanks. Happy to take questions.
]

// ---- references ------------------------------------------------------------

#s([References])[
  #set text(size: 10pt)
  #set par(justify: false)
  #columns(2, gutter: 20pt, bibliography("refs.yml", title: none, style: "ieee"))
]
