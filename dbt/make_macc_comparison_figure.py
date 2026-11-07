from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "analysis_outputs" / "macc_vs_optimizer.csv"
OUT = ROOT / "analysis_outputs" / "figures"
OUT.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(DATA)

# Only buildings with different recommendations
df = df[
    (df["macc_upgrade"] != df["optimizer_upgrade"])
    & (df["extra_cost_usd"] > 0.01)
].copy()

df = df.sort_values("extra_cost_usd", ascending=False)
df["extra_cost_k"] = df["extra_cost_usd"] / 1000

# Short display labels; values and results still come from CSV

# Load upgrade names directly from the MACC analysis.
# No hardcoded upgrade IDs or labels.
upgrade_data = pd.read_csv(
    ROOT / "analysis_outputs" / "macc_options.csv",
    usecols=["upgrade_id", "upgrade_name"]
).drop_duplicates()

upgrade_names = dict(zip(
    upgrade_data["upgrade_id"],
    upgrade_data["upgrade_name"]
))

def option_name(value):
    name = upgrade_names.get(
        int(value), f"Upgrade {int(value)}"
    )

    # Automatically shorten package names for the figure.
    if name.startswith("Package "):
        return name.split(",", 1)[0]

    # Keep other labels within the available column width.
    return name if len(name) <= 27 else name[:24].rstrip() + "..."

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 10,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.spines.left": False,
    "savefig.facecolor": "white",
})

fig = plt.figure(figsize=(12, 6.8), facecolor="white")

ax = fig.add_axes([0.11, 0.19, 0.48, 0.65])
right = fig.add_axes(
    [0.66, 0.19, 0.33, 0.65],
    sharey=ax
)

y = list(range(len(df)))

ax.barh(
    y,
    df["extra_cost_k"],
    height=0.64,
    color="#314E72"
)

ax.set_yticks(y)
ax.set_yticklabels(df["berdo_id"].astype(str))
ax.invert_yaxis()
ax.tick_params(axis="y", length=0, pad=11)
ax.tick_params(axis="x", colors="#526172")

ax.set_xlim(0, df["extra_cost_k"].max() * 1.23)
ax.xaxis.set_major_locator(MultipleLocator(50))
ax.grid(axis="x", color="#E8ECF0", linewidth=0.8)
ax.set_axisbelow(True)
ax.spines["bottom"].set_color("#D5DBE3")

ax.set_xlabel(
    "Additional modeled five-year cost ($ thousands)",
    fontsize=10,
    labelpad=12
)

for i, val in enumerate(df["extra_cost_k"]):
    ax.text(
        val + 3, i, f"${val:,.1f}k",
        ha="left", va="center",
        fontsize=9, color="#233B58"
    )

# Recommendation comparison column
right.set_xlim(0, 1)
right.set_ylim(ax.get_ylim())
right.axis("off")

for i, row in enumerate(df.itertuples()):
    label = (
        f"{option_name(row.macc_upgrade)}"
        f"  →  {option_name(row.optimizer_upgrade)}"
    )
    right.text(
        0, i, label,
        va="center", ha="left",
        fontsize=9, color="#26384E"
    )

# Headings
fig.text(
    0.11, 0.945,
    "MACC versus minimum-cost compliant optimization",
    fontsize=16, fontweight="bold", color="#203856"
)

fig.text(
    0.11, 0.89,
    "Buildings where the recommended retrofit differs",
    fontsize=10.5, color="#596677"
)

fig.text(
    0.11, 0.85, "BERDO ID",
    fontsize=9, fontweight="bold", color="#536477"
)
fig.text(
    0.66, 0.85,
    "MACC recommendation → Optimizer recommendation",
    fontsize=9, fontweight="bold", color="#536477"
)

total = df["extra_cost_usd"].sum()
count = len(df)

fig.text(
    0.11, 0.085,
    f"{count} disagreements  |  "
    f"${total:,.0f} additional modeled cost",
    fontsize=11, fontweight="bold", color="#203856"
)

fig.text(
    0.11, 0.042,
    "Both methods are restricted to emissions-compliant options. "
    "Midpoint costs, 2030–2034.",
    fontsize=9, color="#667383"
)

path = OUT / "macc_vs_optimizer.png"
fig.savefig(path, dpi=250, facecolor="white")
plt.close(fig)

print(f"Saved: {path}")
print(f"Different recommendations: {count}")
print(f"Additional modeled cost: ${total:,.0f}")
