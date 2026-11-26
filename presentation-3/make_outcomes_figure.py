
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

# --------------------------------------------------
# 1. Paths and data
# --------------------------------------------------

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data" / "outcomes.csv"
OUTPUT = ROOT / "img"
OUTPUT.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(DATA).sort_values("ord")

categories = [
    ("acp_only", "No retrofit (ACP only)", "#A8ADB3"),
    ("retrofit_over", "Retrofit, above limit", "#E46B45"),
    ("retrofit_compliant", "Retrofit, meets limit", "#3478BE"),
]

scenario_labels = {
    "5 yr, owner": "5-year · Owner",
    "20 yr, owner": "20-year · Owner",
    "20 yr, society": "20-year · Society",
}

cols = [c[0] for c in categories]
df[cols] = df[cols].astype(int)

totals = df[cols].sum(axis=1)
if totals.nunique() != 1:
    raise ValueError("Scenario cohort sizes must match.")

n = int(totals.iloc[0])

# --------------------------------------------------
# 2. Style
# --------------------------------------------------

NAVY = "#203858"
TEXT = "#384656"
MUTED = "#6B7480"
GRID = "#E6E9ED"

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 12,
    "svg.fonttype": "none",
    "axes.edgecolor": GRID,
    "axes.linewidth": 0.8,
    "savefig.dpi": 300,
})

fig, ax = plt.subplots(figsize=(14, 4.8))
fig.patch.set_facecolor("white")
ax.set_facecolor("white")

fig.subplots_adjust(
    left=0.19,
    right=0.975,
    top=0.72,
    bottom=0.20
)

# --------------------------------------------------
# 3. Stacked bars
# --------------------------------------------------

y_positions = np.arange(len(df))[::-1]
bar_height = 0.58

for y, (_, row) in zip(y_positions, df.iterrows()):

    left = 0

    for column, label, color in categories:
        value = int(row[column])

        if value == 0:
            continue

        ax.barh(
            y,
            value,
            left=left,
            height=bar_height,
            color=color,
            edgecolor="white",
            linewidth=1.2,
            zorder=3
        )

        # Segment labels are calculated from CSV values
        ax.text(
            left + value / 2,
            y,
            f"{value}",
            ha="center",
            va="center",
            fontsize=13,
            fontweight="bold",
            color=NAVY if column == "acp_only" else "white",
            zorder=4
        )

        left += value

# --------------------------------------------------
# 4. Axes and typography
# --------------------------------------------------

ax.set_yticks(y_positions)

ax.set_yticklabels(
    [scenario_labels.get(s, s) for s in df["scenario"]],
    fontsize=13,
    fontweight="bold",
    color=NAVY
)

ax.set_xlim(0, n)
ax.set_ylim(-0.55, len(df) - 0.45)

ticks = np.unique(
    np.rint(np.linspace(0, n, 5)).astype(int)
)

ax.set_xticks(ticks)

ax.set_xlabel(
    "Number of office buildings",
    fontsize=11,
    color=MUTED,
    labelpad=12
)

ax.tick_params(
    axis="x",
    colors=MUTED,
    labelsize=10,
    length=0,
    pad=8
)

ax.tick_params(
    axis="y",
    length=0,
    pad=15
)

ax.set_axisbelow(True)

ax.grid(
    axis="x",
    color=GRID,
    linewidth=0.8,
    alpha=0.75
)

ax.spines[["top", "right", "left"]].set_visible(False)
ax.spines["bottom"].set_color(GRID)

# --------------------------------------------------
# 5. Legend and sample size
# --------------------------------------------------

handles = [
    Patch(facecolor=color, edgecolor="none", label=label)
    for _, label, color in categories
]

fig.legend(
    handles=handles,
    loc="upper left",
    bbox_to_anchor=(0.19, 0.99),
    frameon=False,
    ncol=3,
    fontsize=11,
    handlelength=1.1,
    handleheight=1.1,
    columnspacing=2.6,
    handletextpad=0.7
)

fig.text(
    0.975,
    0.805,
    f"n = {n} offices per scenario",
    ha="right",
    fontsize=10.5,
    color=MUTED
)

# --------------------------------------------------
# 6. Export vector and high-resolution raster
# --------------------------------------------------

for extension in ["svg", "png"]:
    output_path = OUTPUT / f"optimizer_outcomes.{extension}"

    fig.savefig(
        output_path,
        dpi=300,
        facecolor="white",
        bbox_inches="tight",
        pad_inches=0.12
    )

    print(f"Saved: {output_path}")

plt.close(fig)

