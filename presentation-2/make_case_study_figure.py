
from pathlib import Path
import re
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

# --------------------------------------------------
# Load actual model output
# --------------------------------------------------

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data" / "case_study.csv"
OUT = ROOT / "img"
OUT.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(DATA)
df = df.sort_values("upgrade_id").reset_index(drop=True)

scenarios = [
    ("5-year owner", "delta_5yr_owner"),
    ("20-year owner", "delta_20yr_owner"),
    ("20-year society", "delta_20yr_society"),
]

def short_name(name):
    if name.lower().startswith("no upgrade"):
        return "No retrofit"
    match = re.match(r"Package \d+", name)
    if match:
        return match.group(0)
    return name.capitalize()

def best_option(column):
    return df.sort_values(
        [column, "upgrade_id"]
    ).iloc[0]

def format_cost(value):
    if abs(value) < 0.5:
        return "$0"
    sign = "+" if value > 0 else "−"
    return f"{sign}${abs(value) / 1000:,.0f}k"

# Identify options dynamically
owner_best = best_option("delta_20yr_owner")
society_best = best_option("delta_20yr_society")

comparison = (
    pd.DataFrame([owner_best, society_best])
    .drop_duplicates(subset="upgrade_id")
    .reset_index(drop=True)
)

# --------------------------------------------------
# Figure style
# --------------------------------------------------

NAVY = "#203858"
BLUE = "#3478BE"
ORANGE = "#D96745"
MUTED = "#65717F"
LINE = "#DDE3E9"
SHADE = "#F5F7F9"

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "font.size": 12,
})

fig, ax = plt.subplots(figsize=(13.5, 4.8))
fig.patch.set_facecolor("white")
ax.set_xlim(0, 1)
ax.set_ylim(0, 1)
ax.axis("off")

# Column positions
x_scenario = 0.035
option_x = np.linspace(0.59, 0.85, len(comparison))

# --------------------------------------------------
# Column headings
# --------------------------------------------------

ax.text(
    x_scenario, 0.89,
    "SCENARIO / LOWEST-COST CHOICE",
    fontsize=12, fontweight="bold",
    color=NAVY, va="center"
)

for j, (_, option) in enumerate(comparison.iterrows()):
    ax.text(
        option_x[j], 0.89,
        short_name(option["upgrade_name"]),
        ha="center", va="center",
        fontsize=14,
        fontweight="bold",
        color=ORANGE if j == 0 else BLUE
    )

ax.plot(
    [0.035, 0.965], [0.83, 0.83],
    color=NAVY, linewidth=1.5
)

# --------------------------------------------------
# Table rows
# --------------------------------------------------

row_centers = [0.69, 0.47, 0.25]

for i, ((scenario, column), y) in enumerate(
    zip(scenarios, row_centers)
):
    choice = best_option(column)

    # Subtle alternating background
    if i % 2 == 0:
        ax.add_patch(
            plt.Rectangle(
                (0.035, y - 0.095),
                0.93, 0.19,
                facecolor=SHADE,
                edgecolor="none",
                zorder=0
            )
        )

    ax.text(
        x_scenario, y + 0.028,
        scenario,
        fontsize=14,
        fontweight="bold",
        color=NAVY,
        va="center"
    )

    ax.text(
        x_scenario, y - 0.040,
        f"Selected: {short_name(choice['upgrade_name'])}",
        fontsize=11,
        color=MUTED,
        va="center"
    )

    for j, (_, option) in enumerate(comparison.iterrows()):
        value = float(option[column])

        # Emphasize the model's selected option
        selected = (
            int(choice["upgrade_id"])
            == int(option["upgrade_id"])
        )

        ax.text(
            option_x[j], y,
            format_cost(value),
            ha="center",
            va="center",
            fontsize=18,
            fontweight="bold" if selected else "medium",
            color=ORANGE if j == 0 else BLUE
        )

# --------------------------------------------------
# Notes
# --------------------------------------------------

ax.plot(
    [0.035, 0.965], [0.12, 0.12],
    color=LINE, linewidth=0.8
)

ax.text(
    0.035, 0.063,
    "Positive = additional cost; negative = savings "
    "relative to no retrofit under the same scenario.",
    fontsize=10.5,
    color=MUTED,
    va="center"
)

# Check for tied minima
ties = df[
    np.isclose(
        df["delta_20yr_society"],
        society_best["delta_20yr_society"],
        atol=0.01
    )
]

if len(ties) > 1:
    names = ", ".join(
        short_name(x) for x in ties["upgrade_name"]
    )
    print(f"Societal minimum is tied: {names}")

# --------------------------------------------------
# Export
# --------------------------------------------------

for ext in ["svg", "png"]:
    path = OUT / f"case_study_cost_comparison.{ext}"
    fig.savefig(
        path,
        dpi=300,
        bbox_inches="tight",
        pad_inches=0.12,
        facecolor="white"
    )
    print(f"Saved: {path}")

plt.close(fig)
