
from pathlib import Path
import json
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator

# --------------------------------------------------
# 1. Load actual optimizer results
# --------------------------------------------------

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
OUT = ROOT / "img"
OUT.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(DATA / "breakeven.csv")
stats = json.loads((DATA / "stats.json").read_text())

rates = df["breakeven_acp_usd_per_t"].dropna()
acp = float(stats["acp_usd_per_t"])
n_compliant = len(rates)
n_over_limit = int(stats["over_limit"])
n_no_option = n_over_limit - n_compliant
median = rates.median()

# --------------------------------------------------
# 2. Calculate histogram counts
# --------------------------------------------------

bins = [-np.inf, acp, 500, 1000, 2000, np.inf]

labels = [
    f"≤ ${acp:,.0f}",
    f"${acp:,.0f}–500",
    "$500–1k",
    "$1k–2k",
    "> $2k",
]

counts = pd.cut(
    rates,
    bins=bins,
    labels=labels,
    include_lowest=True
).value_counts().reindex(labels, fill_value=0)

n_at_current = int((rates <= acp).sum())

# --------------------------------------------------
# 3. Professional figure styling
# --------------------------------------------------

NAVY = "#203858"
BLUE = "#3478BE"
GRAY = "#ACB2B8"
TEXT = "#414B57"
MUTED = "#717B86"
GRID = "#E7EAEF"

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 12,
    "svg.fonttype": "none",
    "axes.linewidth": 0.8,
})

fig = plt.figure(figsize=(14, 5.2), facecolor="white")

# Leave room on the right for interpretation
ax = fig.add_axes([0.08, 0.24, 0.59, 0.60])

x = np.arange(len(labels))
colors = [BLUE] + [GRAY] * (len(labels) - 1)

bars = ax.bar(
    x,
    counts.values,
    width=0.67,
    color=colors,
    edgecolor="none",
    zorder=3
)

# Counts above bars
for bar, count in zip(bars, counts.values):
    ax.text(
        bar.get_x() + bar.get_width() / 2,
        bar.get_height() + 0.5,
        str(int(count)),
        ha="center",
        va="bottom",
        fontsize=13,
        fontweight="bold",
        color=NAVY
    )

# --------------------------------------------------
# 4. Axes
# --------------------------------------------------

ax.set_xticks(x)
ax.set_xticklabels(labels, fontsize=11, color=TEXT)

ax.set_ylabel(
    "Number of buildings",
    fontsize=12,
    color=TEXT,
    labelpad=12
)

ax.set_xlabel(
    "Break-even ACP rate ($/tCO₂e)",
    fontsize=12,
    color=TEXT,
    labelpad=15
)

ax.set_ylim(0, max(counts.values) * 1.23)
ax.yaxis.set_major_locator(MultipleLocator(5))

ax.tick_params(
    axis="both",
    which="both",
    length=0,
    labelcolor=MUTED,
    pad=8
)

ax.grid(
    axis="y",
    color=GRID,
    linewidth=0.8,
    zorder=0
)

ax.spines[["top", "right", "left"]].set_visible(False)
ax.spines["bottom"].set_color(GRID)

# --------------------------------------------------
# 5. Interpretation on the right
# --------------------------------------------------

fig.text(
    0.73, 0.82,
    "KEY FINDINGS",
    fontsize=11,
    fontweight="bold",
    color=MUTED
)

fig.text(
    0.73, 0.70,
    f"Median break-even: ${median:,.0f}/tCO₂e",
    fontsize=14,
    fontweight="bold",
    color=NAVY
)

fig.text(
    0.73, 0.59,
    f"{n_at_current} buildings become cost-effective\n"
    f"at or below ${acp:,.0f}/tCO₂e.",
    fontsize=12,
    color=TEXT,
    linespacing=1.5
)

fig.text(
    0.73, 0.42,
    f"{n_no_option} of {n_over_limit} buildings have no\n"
    "modeled compliant retrofit.",
    fontsize=12,
    color=TEXT,
    linespacing=1.5
)

fig.text(
    0.08, 0.93,
    f"Break-even distribution for {n_compliant} buildings "
    "with a compliant retrofit",
    fontsize=13,
    color=NAVY,
    fontweight="bold"
)

# --------------------------------------------------
# 6. Save SVG and PNG
# --------------------------------------------------

for ext in ["svg", "png"]:
    path = OUT / f"breakeven_distribution.{ext}"

    fig.savefig(
        path,
        dpi=300,
        bbox_inches="tight",
        pad_inches=0.15,
        facecolor="white"
    )

    print(f"Saved: {path}")

plt.close(fig)

print("Bin counts:")
print(counts)
print(f"Median: ${median:,.1f}/tCO2e")
