"""Report 2's data figures, drawn from the dbt models in one shared style:

    figures/berdo-completeness.png     data completeness by building use
    figures/berdo-mixed-use-cdf.png    cumulative distribution of the mixed-use share
    figures/berdo-intensity-cdf.png    cumulative distribution of reported GHG intensity
    figures/breakeven-acp.png          over-limit offices a compliant retrofit wins, by ACP rate
    figures/compliance-outcomes.svg    compliance of the minimum-global-cost recommendations
    figures/global-k-sensitivity.svg   recommendation changes relative to the configured k

Run from the repo root after `dbt build`:
    uv run python report-2/make_berdo_figures.py

Offices are buildings whose largest property type is Office or Financial Office, as in dbt's
var("match_property_types"). Medical Office is left out: BERDO counts it as Healthcare, with
its own emissions limits. Inside an office building it is another use.
"""

from __future__ import annotations

import csv
from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import yaml
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.ticker import PercentFormatter

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "dbt" / "ds5500.duckdb"
OUTPUTS = DB.parent / "analysis_outputs"
VARS = yaml.safe_load((DB.parent / "dbt_project.yml").read_text(encoding="utf-8"))["vars"]
FIGURES = Path(__file__).resolve().parent / "figures"

OFFICE_TYPES = ("Office", "Financial Office")
OFFICE_LABEL = "Office + Financial Office"
LIMIT_2030 = 3.2  # BERDO office standard for 2030-2034, kg CO2e/ft²/yr

# reference palette: categorical slot 1, the text inks, and the blue sequential ramp
SERIES = "#2a78d6"
INK = "#0b0b0b"
INK_2 = "#52514e"
GRID = "#e4e3df"
BLUES = ["#f3f7fd", "#cde2fb", "#86b6ef", "#3987e5", "#1c5cab", "#0d366b"]

plt.rcParams.update({"font.size": 10, "font.family": "serif"})


def style_axes(ax: plt.Axes, ylabel: str, xlabel: str) -> None:
    """Recessive axes, y gridlines only, and the y label unrotated above the axis."""
    ax.set_xlabel(xlabel, color=INK)
    ax.set_ylabel(ylabel, color=INK, rotation=0, ha="left", va="bottom")
    ax.yaxis.set_label_coords(-0.075, 1.04)
    ax.grid(axis="y", color=GRID, linewidth=0.7)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(INK_2)
    ax.tick_params(colors=INK_2)


def point(ax: plt.Axes, x: float, y: float, text: str, xytext: tuple[float, float]) -> None:
    """A marked point on the curve with a leader line to its label."""
    ax.plot([x], [y], marker="o", markersize=7, color=SERIES,
            markeredgecolor="white", markeredgewidth=1.5, zorder=3, clip_on=False)
    ax.annotate(text, xy=(x, y), xytext=xytext, color=INK, fontsize=9.5,
                arrowprops={"arrowstyle": "-", "color": INK_2, "linewidth": 0.8})


def save(fig: plt.Figure, name: str) -> None:
    fig.tight_layout()
    FIGURES.mkdir(parents=True, exist_ok=True)
    out = FIGURES / name
    fig.savefig(out, facecolor="white")
    plt.close(fig)
    print(f"wrote {out.relative_to(ROOT)}")


# ---- Fig. 3: completeness ----------------------------------------------------------

COMPLETENESS_COLUMNS = {
    "gfa_sqft": "Gross\nfloor area",
    "ghg_kgco2e": "GHG\nemissions",
    "reported_ghg_intensity_kgco2e_sqft": "GHG\nintensity",
    "compliance_standard_kgco2e_sqft": "Emissions\nstandard",
    "site_energy_kwh": "Site\nenergy",
    "reported_site_eui_kbtu_sqft": "Site\nEUI",
}


def completeness(con: duckdb.DuckDBPyConnection) -> None:
    cols = list(COMPLETENESS_COLUMNS)
    rows = con.sql(f"""
        with typed as (
            select
                case when property_type in {OFFICE_TYPES} then '{OFFICE_LABEL}'
                    else property_type end as building_use,
                *
            from stg_berdo__buildings
            where property_type is not null
        ),

        -- the four most common other uses, next to the offices
        uses as (
            (select building_use from typed where building_use <> '{OFFICE_LABEL}'
             group by building_use order by count(*) desc limit 4)
            union all
            select '{OFFICE_LABEL}'
        )

        select
            building_use,
            count(*) as records,
            {", ".join(f"100.0 * count({c}) / count(*)" for c in cols)}
        from typed
        inner join uses using (building_use)
        group by building_use
        order by records desc
    """).fetchall()

    labels = [f"{r[0]} (n = {r[1]:,})" for r in rows]
    values = np.array([r[2:] for r in rows], dtype=float)
    for label, v in zip(labels, values):
        print(f"{label}: " + ", ".join(f"{x:.1f}" for x in v))

    cmap = LinearSegmentedColormap.from_list("blues", BLUES)
    fig, ax = plt.subplots(figsize=(7.5, 3.0), dpi=220)
    ax.imshow(values, cmap=cmap, vmin=0, vmax=100, aspect="auto")
    # a 2px surface gap between cells
    ax.set_xticks(np.arange(-0.5, values.shape[1]), minor=True)
    ax.set_yticks(np.arange(-0.5, values.shape[0]), minor=True)
    ax.grid(which="minor", color="white", linewidth=2)
    ax.tick_params(which="both", length=0, colors=INK)
    for i, j in np.ndindex(values.shape):
        v = values[i, j]
        ax.text(j, i, f"{v:.1f}", ha="center", va="center", fontsize=9.5,
                color="white" if v >= 60 else INK)

    ax.set_xticks(range(len(cols)), [COMPLETENESS_COLUMNS[c] for c in cols])
    ax.xaxis.tick_top()
    ax.set_yticks(range(len(labels)), labels)
    for spine in ax.spines.values():
        spine.set_visible(False)
    save(fig, "berdo-completeness.png")


# ---- Fig. 4: mixed-use share ----------------------------------------------------------

def mixed_use(con: duckdb.DuckDBPyConnection) -> int:
    rows = con.sql(f"""
        with offices as (
            select berdo_id
            from stg_berdo__buildings
            where berdo_id is not null and property_type in {OFFICE_TYPES}
        ),

        -- the non-office, non-parking share, over the listed non-parking floor area
        shares as (
            select
                berdo_id,
                1 - coalesce(sum(non_parking_gfa_share) filter (
                    where property_type in {OFFICE_TYPES}
                ), 0) as other_share
            from int_berdo_building_property_types
            group by berdo_id
        )

        select o.berdo_id, s.other_share
        from offices as o
        left join shares as s using (berdo_id)
    """).fetchall()
    missing = [b for b, s in rows if s is None]
    if missing:
        raise SystemExit(f"{len(missing)} offices have no property-type list: {missing[:5]}")

    share = np.sort(np.array([s for _, s in rows]))
    # shares of exactly zero can come out as tiny float residue from the window sums
    share[share < 1e-9] = 0.0
    n = len(share)
    office_only = int((share == 0).sum())
    mixed = share[share > 0]
    # 95th percentile as the empirical CDF's inverse: the smallest share with F >= 0.95
    p95 = share[int(np.ceil(0.95 * n)) - 1]

    print(f"offices: {n}")
    print(f"office/parking only: {office_only} ({office_only / n:.1%})")
    print(f"any other use: {n - office_only} ({(n - office_only) / n:.1%})")
    print(f"median mixed-use share among mixed-use offices: {np.median(mixed):.1%}")
    print(f"95th percentile: {p95:.1%}")

    # empirical CDF as a step, starting at the office-only share on the y-axis rather than
    # rising from 0 along it
    xs = np.concatenate((share[office_only - 1:], [0.75]))
    ys = np.concatenate((np.arange(office_only, n + 1) / n, [1.0]))

    fig, ax = plt.subplots(figsize=(7.5, 3.4), dpi=220)
    ax.step(xs, ys, where="post", color=SERIES, linewidth=2)
    point(ax, 0, office_only / n,
          f"{office_only} of {n} ({office_only / n:.0%}) have only\noffice and parking space",
          (0.035, office_only / n - 0.17))
    point(ax, p95, 0.95, f"95th percentile: {p95:.1%}\nmixed-use share", (p95 + 0.04, 0.70))
    ax.set_xlim(0, 0.75)
    ax.set_ylim(0, 1.02)
    ax.xaxis.set_major_formatter(PercentFormatter(1.0, decimals=0))
    ax.yaxis.set_major_formatter(PercentFormatter(1.0, decimals=0))
    style_axes(ax, f"Cumulative share of offices (n = {n})", "Mixed-use share of floor area")
    save(fig, "berdo-mixed-use-cdf.png")
    return n


# ---- Fig. 5: reported GHG intensity ----------------------------------------------------

def intensity(con: duckdb.DuckDBPyConnection) -> tuple[int, int]:
    counts = con.sql(f"""
        select count(*), count(reported_ghg_intensity_kgco2e_sqft)
        from stg_berdo__buildings
        where property_type in {OFFICE_TYPES}
    """).fetchall()[0]
    ghg = np.sort(np.array([r[0] for r in con.sql(f"""
        select reported_ghg_intensity_kgco2e_sqft
        from stg_berdo__buildings
        where property_type in {OFFICE_TYPES} and reported_ghg_intensity_kgco2e_sqft >= 0
    """).fetchall()]))
    n = len(ghg)
    over = int((ghg > LIMIT_2030).sum())
    at_limit = (n - over) / n  # the CDF at the limit
    xmax = float(np.ceil(ghg.max()))

    print(f"offices: {counts[0]}, with GHG intensity: {counts[1]}, valid (>= 0): {n}")
    print(f"missing GHG intensity: {counts[0] - counts[1]} ({(counts[0] - counts[1]) / counts[0]:.1%})")
    print(f"over {LIMIT_2030}: {over} ({over / n:.1%})")
    print(f"median: {np.median(ghg):.2f}, max: {ghg.max():.2f}")

    xs = np.concatenate(([0.0], ghg, [xmax]))
    ys = np.concatenate(([0.0], np.arange(1, n + 1) / n, [1.0]))

    fig, ax = plt.subplots(figsize=(7.5, 3.4), dpi=220)
    ax.axvline(LIMIT_2030, color=INK_2, linewidth=1, linestyle=(0, (4, 3)), zorder=1)
    ax.text(LIMIT_2030 + 0.12, 0.05, f"2030 office limit: {LIMIT_2030}", color=INK_2, fontsize=9.5)
    ax.step(xs, ys, where="post", color=SERIES, linewidth=2)
    point(ax, LIMIT_2030, at_limit,
          f"{over} of {n} ({over / n:.0%}) are above\nthe 2030 limit",
          (LIMIT_2030 + 1.2, at_limit - 0.25))
    ax.set_xlim(0, xmax)
    ax.set_ylim(0, 1.02)
    ax.yaxis.set_major_formatter(PercentFormatter(1.0, decimals=0))
    style_axes(ax, f"Cumulative share of offices (n = {n})",
               "Reported GHG emissions intensity (kg CO$_2$e/ft²/yr)")
    save(fig, "berdo-intensity-cdf.png")
    return counts[0], n


# ---- break-even ACP ----------------------------------------------------------------

ACP_USD_PER_T = VARS["acp_usd_per_tco2e"]
BREAKEVEN_XMAX = 2000


def breakeven(con: duckdb.DuckDBPyConnection) -> None:
    # the over-limit cohort, and the break-even rate of those with a compliant option
    cohort = con.sql("""
        select count(*) from berdo_global_cost
        where scenario = 'projected' and energy_price = 'mid' and perspective = 'financial'
          and upgrade_id = 0 and not meets_standard_at_start
    """).fetchall()[0][0]
    be = np.sort(np.array([r[0] for r in con.sql(
        "select breakeven_acp_usd_per_t from analysis_breakeven_acp"
    ).fetchall()]))
    n = len(be)
    today = int((be <= ACP_USD_PER_T).sum())
    shown = be[be <= BREAKEVEN_XMAX]
    above = n - len(shown)

    print(f"over-limit offices: {cohort}, with a compliant option: {n}")
    print(f"compliant cheapest at ${ACP_USD_PER_T}: {today}; above ${BREAKEVEN_XMAX:,}: {above}")
    print(f"median break-even: ${np.median(be):,.0f}; above $1,000: {int((be > 1000).sum())}")

    # starts at the offices that break even at $0 on the y-axis, as in the mixed-use figure
    at_zero = int((shown == 0).sum())
    xs = np.concatenate((shown[at_zero - 1:], [BREAKEVEN_XMAX])) if at_zero else \
        np.concatenate(([0.0], shown, [BREAKEVEN_XMAX]))
    ys = np.concatenate((np.arange(max(at_zero, 1), len(shown) + 1), [len(shown)])) if at_zero else \
        np.concatenate(([0], np.arange(1, len(shown) + 1), [len(shown)]))
    print(f"compliant cheapest even with no ACP: {at_zero}")

    fig, ax = plt.subplots(figsize=(7.5, 3.4), dpi=220)
    # the most the curve can reach: offices without a compliant option never tip
    ax.axhline(n, color=INK_2, linewidth=1, linestyle=(0, (1, 2)), zorder=1)
    ax.text(BREAKEVEN_XMAX, n + 1.2, f"{cohort - n} of {cohort} offices have no compliant retrofit",
            ha="right", va="bottom", color=INK_2, fontsize=9.5)
    ax.axvline(ACP_USD_PER_T, color=INK_2, linewidth=1, linestyle=(0, (4, 3)), zorder=1)
    ax.text(ACP_USD_PER_T + 25, 2, f"Today's ACP: ${ACP_USD_PER_T}/t", color=INK_2, fontsize=9.5)
    ax.step(xs, ys, where="post", color=SERIES, linewidth=2)
    if at_zero:
        point(ax, 0, at_zero, f"{at_zero} pick it\nwith no ACP", (15, at_zero + 16))
    point(ax, ACP_USD_PER_T, today, f"{today} of {n} offices with a compliant\noption already pick it",
          (ACP_USD_PER_T + 180, today - 14))
    ax.text(BREAKEVEN_XMAX, len(shown) + 1.5, f"{above} more above ${BREAKEVEN_XMAX:,}",
            ha="right", va="bottom", color=INK_2, fontsize=9.5)
    ax.set_xlim(0, BREAKEVEN_XMAX)
    ax.set_ylim(0, cohort + 2)
    ax.set_yticks([0, 20, 40, 60, cohort])
    ax.xaxis.set_major_formatter(lambda x, _: f"${x:,.0f}")
    style_axes(ax, f"Over-limit offices where a compliant retrofit is the owner's cheapest option (of {cohort})",
               r"ACP rate (\$ per metric ton of CO$_2$e)")
    save(fig, "breakeven-acp.png")


def analysis_rows(path: str) -> list[dict[str, str]]:
    with (OUTPUTS / path).open(newline="", encoding="utf-8") as file:
        return list(csv.DictReader(file))


def save_results_svg(fig: plt.Figure, name: str) -> None:
    fig.savefig(FIGURES / name, bbox_inches="tight", pad_inches=0.03,
                metadata={"Date": None})
    plt.close(fig)


def compliance_outcomes() -> None:
    rows = {r["perspective"]: r for r in analysis_rows("energy_scenario_outcomes.csv")
            if r["scenario"] == "projected"}
    labels = ("Owner", "Society")
    perspectives = ("financial", "societal")
    counts = []
    for perspective in perspectives:
        row = rows[perspective]
        total = int(row["offices"]) - int(row["under_limit_anyway"])
        good = int(row["retrofit_compliant"])
        other = int(row["retrofit_over"]) + int(row["no_retrofit"])
        if good + other != total:
            raise ValueError(f"Inconsistent compliance counts for {perspective}")
        counts.append((good, other))
    cohort = sum(counts[0])
    if sum(counts[1]) != cohort:
        raise ValueError("Compliance perspectives use different cohorts")

    fig, ax = plt.subplots(figsize=(3.45, 1.23))
    for i, (good, other) in enumerate(counts):
        ax.barh(i, good, color="#245b86", height=0.55)
        ax.barh(i, other, left=good, color="#dce7ef", height=0.55)
        ax.text(good / 2, i, f"{good} meet limit", ha="center", va="center",
                color="white", fontsize=8)
        ax.text(good + other / 2, i, f"{other} over limit", ha="center", va="center",
                fontsize=8)
    ax.set(yticks=range(len(labels)), yticklabels=labels, xlim=(0, cohort),
           xticks=[*range(0, cohort - 5, 20), cohort], xlabel="Office buildings")
    ax.invert_yaxis()
    ax.tick_params(axis="y", length=0, pad=4)
    for edge in ("left", "right", "top"):
        ax.spines[edge].set_visible(False)
    save_results_svg(fig, "compliance-outcomes.svg")


def global_k_sensitivity() -> None:
    rows = analysis_rows("k_sensitivity/data/global_k_summary.csv")
    k_ref = VARS["match_k"]
    neighbors = list(range(1, k_ref + 1))
    series = []
    for perspective in ("financial", "societal"):
        data = sorted((r for r in rows if r["perspective"] == perspective), key=lambda r: int(r["k"]))
        if [int(r["k"]) for r in data] != neighbors:
            raise ValueError(f"Unexpected neighbor sweep for {perspective}")
        series.append(data)
    panels = (
        ("Cheapest overall", "cheapest_changed_vs_ref"),
        ("Cheapest compliant", "cheapest_compliant_changed_vs_ref"),
    )
    peak = max(int(r[key]) for rows in series for r in rows for _, key in panels)
    upper = max(20, 20 * ((peak + 19) // 20))
    fig, axes = plt.subplots(1, 2, figsize=(6.5, 2.25), sharey=True)
    for ax, (title, key) in zip(axes, panels):
        for data, label, color, marker in zip(
            series, ("Owner", "Society"), ("#245b86", "#a65021"), ("o", "s")
        ):
            ax.plot(neighbors, [int(r[key]) for r in data], label=label, color=color,
                    marker=marker, ms=2.6, lw=1.2)
        ax.set(title=title, xlabel="Neighbors (k)",
               xticks=sorted({1, k_ref, *range(5, k_ref, 5)}), ylim=(0, upper))
        ax.grid(axis="y", alpha=0.25)
        for edge in ("right", "top"):
            ax.spines[edge].set_visible(False)
    axes[0].set_ylabel("Offices with a different choice")
    axes[1].legend(frameon=False, loc="upper right")
    fig.tight_layout()
    save_results_svg(fig, "global-k-sensitivity.svg")


def main() -> None:
    with duckdb.connect(str(DB), read_only=True) as con:
        completeness(con)
        mixed_use_count = mixed_use(con)
        office_records, intensity_count = intensity(con)
        breakeven(con)
    with (OUTPUTS / "berdo_figure_counts.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(("mixed_use_offices", "office_records", "reported_intensity_offices"))
        writer.writerow((mixed_use_count, office_records, intensity_count))
    with plt.rc_context({"font.size": 9, "svg.fonttype": "path", "svg.hashsalt": "ds5500-report-2"}):
        compliance_outcomes()
        global_k_sensitivity()


if __name__ == "__main__":
    main()
