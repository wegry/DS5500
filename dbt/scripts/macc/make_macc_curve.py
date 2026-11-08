from pathlib import Path

import polars as pl
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib.ticker import FuncFormatter


BASE_DIR = Path(__file__).resolve().parents[2]
INPUT_CSV = BASE_DIR / "analysis_outputs" / "macc" / "data" / "macc_options.csv"
OUTPUT_DIR = BASE_DIR / "analysis_outputs" / "macc" / "figures"
OUTPUT_PNG = OUTPUT_DIR / "macc_curve.png"
OUTPUT_SVG = OUTPUT_DIR / "macc_curve.svg"

MAX_DISPLAY_MAC = 3000

BLUE = "#4E79A7"
ORANGE = "#C98255"
TEXT = "#5F6F82"
GRID = "#D9DEE5"


def pick_col(df: pl.DataFrame, candidates: list[str]) -> str:
    for c in candidates:
        if c in df.columns:
            return c
    raise KeyError(f"Could not find any of these columns: {candidates}")


def load_selected_macc_options() -> tuple[pl.DataFrame, dict[str, str]]:
    df = pl.read_csv(INPUT_CSV)

    berdo_col = pick_col(df, ["berdo_id"])
    name_col = pick_col(df, ["upgrade_name"])
    mac_col = pick_col(df, ["mac_usd_per_ton", "macc_usd_per_ton"])
    avoided_col = pick_col(df, ["avoided_tons", "avoided_tco2e", "avoided_emissions_tons"])
    meets_col = pick_col(df, ["meets_standard"])

    if "selected_lowest_mac" in df.columns:
        if df.schema["selected_lowest_mac"] == pl.String:
            df = df.with_columns(
                pl.col("selected_lowest_mac").str.to_lowercase().eq("true").alias("selected_lowest_mac")
            )
        selected = (
            df.filter(pl.col("selected_lowest_mac"))
              .filter(pl.col(avoided_col) > 0)
              .filter(pl.col(mac_col).is_not_null())
        )
    else:
        selected = (
            df.filter(pl.col(meets_col))
              .filter(pl.col(avoided_col) > 0)
              .filter(pl.col(mac_col).is_not_null())
              .sort([berdo_col, mac_col, avoided_col], descending=[False, False, True])
              .unique(subset=[berdo_col], keep="first", maintain_order=True)
        )

    selected = (
        selected.sort(mac_col)
                .with_columns(pl.col(avoided_col).cum_sum().alias("cum_end"))
                .with_columns([
                    (pl.col("cum_end") - pl.col(avoided_col)).alias("x_start"),
                    pl.when(pl.col(mac_col) > MAX_DISPLAY_MAC)
                      .then(MAX_DISPLAY_MAC)
                      .otherwise(pl.col(mac_col))
                      .alias("plot_mac"),
                    (pl.col(mac_col) > MAX_DISPLAY_MAC).alias("is_truncated"),
                ])
    )

    cols = {
        "berdo": berdo_col,
        "name": name_col,
        "mac": mac_col,
        "avoided": avoided_col,
    }
    return selected, cols


def money_fmt_0(x, pos=None):
    return f"${x:,.0f}"


def k_fmt(x, pos=None):
    return f"{int(round(x / 1000.0))}k"


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    selected, cols = load_selected_macc_options()

    berdo_col = cols["berdo"]
    name_col = cols["name"]
    mac_col = cols["mac"]
    avoided_col = cols["avoided"]

    x_start = selected["x_start"].to_list()
    widths = selected[avoided_col].to_list()
    heights = selected["plot_mac"].to_list()
    is_truncated = selected["is_truncated"].to_list()
    colors = [ORANGE if flag else BLUE for flag in is_truncated]

    total_abatement = float(selected[avoided_col].sum())
    n_buildings = selected.height
    median_mac = float(selected[mac_col].median())
    high_cost = selected.filter(pl.col("is_truncated"))
    n_high_cost = high_cost.height

    top_high = (
        selected.sort(mac_col, descending=True)
                .select([berdo_col, name_col, mac_col])
                .head(3)
                .to_dicts()
    )

    fig = plt.figure(figsize=(16, 8.8), facecolor="white")
    gs = fig.add_gridspec(1, 2, width_ratios=[5.2, 1.6], wspace=0.28)

    ax = fig.add_subplot(gs[0, 0])
    side = fig.add_subplot(gs[0, 1])
    side.axis("off")

    ax.bar(
        x_start,
        heights,
        width=widths,
        align="edge",
        color=colors,
        edgecolor="white",
        linewidth=0.9,
        zorder=3,
    )

    ax.set_xlim(0, total_abatement * 1.005)
    ax.set_ylim(0, MAX_DISPLAY_MAC * 1.04)

    ax.set_xlabel("Cumulative five-year emissions avoided (tCO₂e)", fontsize=13, labelpad=12)
    ax.set_ylabel("Marginal abatement cost ($/tCO₂e)", fontsize=13, labelpad=12)

    ax.xaxis.set_major_formatter(FuncFormatter(k_fmt))
    ax.yaxis.set_major_formatter(FuncFormatter(money_fmt_0))

    ax.grid(axis="y", color=GRID, linewidth=1.0, zorder=0)
    ax.grid(axis="x", visible=False)

    ax.tick_params(axis="both", labelsize=11)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    legend_handles = [
        Patch(facecolor=BLUE, edgecolor="white", label=f"MAC ≤ ${MAX_DISPLAY_MAC:,.0f}/t"),
        Patch(facecolor=ORANGE, edgecolor="white", label=f"MAC > ${MAX_DISPLAY_MAC:,.0f}/t (height truncated)"),
    ]
    ax.legend(handles=legend_handles, loc="upper left", frameon=False, fontsize=11)

    fig.suptitle("Marginal Abatement Cost Curve", fontsize=28, fontweight="bold", x=0.12, ha="left", y=0.97)
    fig.text(0.12, 0.915, "Lowest-MAC compliant retrofit per individual Boston office", fontsize=16, color=TEXT)

    side.text(0.0, 0.98, "HIGH-COST PROJECTS", fontsize=18, fontweight="bold", va="top")
    side.text(0.0, 0.88, f"{n_high_cost} of {n_buildings} above ${MAX_DISPLAY_MAC:,.0f}/t", fontsize=14, color=TEXT)

    y = 0.74
    for row in top_high:
        side.text(0.0, y, f"Building {int(row[berdo_col])}", fontsize=14, color=TEXT)
        side.text(0.0, y - 0.07, f"${row[mac_col]:,.0f}/tCO₂e", fontsize=20, fontweight="bold", color=ORANGE)
        y -= 0.18

    side.text(0.0, 0.06, "Exact costs retained in the data.", fontsize=12.5, color=TEXT)

    summary = (
        f"{n_buildings} buildings  |  {total_abatement:,.0f} tCO₂e avoided  |  "
        f"Median MAC: ${median_mac:,.0f}/t  |  2030–2034"
    )
    fig.text(0.12, 0.12, summary, fontsize=14, fontweight="bold", color="#455A73")

    note = (
        "Modeled retrofit opportunities, not optimizer-selected investments. "
        "Each building appears once; orange bars exceed the displayed cost range."
    )
    fig.text(0.12, 0.075, note, fontsize=11.5, color=TEXT)

    fig.subplots_adjust(left=0.12, right=0.97, top=0.86, bottom=0.20, wspace=0.28)

    fig.savefig(OUTPUT_PNG, dpi=300, bbox_inches="tight")
    fig.savefig(OUTPUT_SVG, bbox_inches="tight")
    plt.close(fig)

    print(f"Saved: {OUTPUT_PNG}")
    print(f"Saved: {OUTPUT_SVG}")
    print(f"Buildings represented: {n_buildings}")
    print(f"Total five-year abatement (tons): {total_abatement:.2f}")
    print(f"Median MAC ($/ton): {median_mac:.2f}")
    print(f"Projects above ${MAX_DISPLAY_MAC:,.0f}/ton: {n_high_cost}")


if __name__ == "__main__":
    main()