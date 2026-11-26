
from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt

# Paths relative to this script
ROOT = Path(__file__).resolve().parent
DATA = ROOT.parent / "dbt" / "analysis_outputs" / "farnsworth_106476_options.csv"
OUT = ROOT / "img"
OUT.mkdir(parents=True, exist_ok=True)

# Load actual optimizer output
df = pd.read_csv(DATA).sort_values("cost_rank_mid")
df["meets_standard"] = (
    df["meets_standard"].astype(str).str.lower() == "true"
)

# Shorter labels for presentation readability
labels = {
    0: "No upgrade (ACP only)",
    43: "LED lighting",
    48: "Wall insulation",
    49: "Roof insulation",
    52: "New windows",
    54: "Pkg 1: walls + roof + windows",
    55: "Pkg 2: LED + variable-speed HP",
    56: "Pkg 3: Pkg 1 + Pkg 2",
    57: "Pkg 4: LED + standard HP",
}

def money(value):
    return f"${value:,.0f}"

best_overall = df["total_5yr_usd"].min()
compliant = df[df["meets_standard"]]
best_compliant = compliant["total_5yr_usd"].min()
premium = best_compliant - best_overall

columns = [
    "Retrofit option",
    "GHG\nkg/ft²/yr",
    "Meets\nlimit?",
    "Install",
    "ACP (5 yr)",
    "Energy (5 yr)",
    "Total (5 yr)",
]

rows = []
for _, r in df.iterrows():
    rows.append([
        labels.get(int(r["upgrade_id"]), r["upgrade_name"]),
        f'{r["projected_ghg"]:.2f}',
        "Yes" if r["meets_standard"] else "No",
        money(r["installation_usd"]),
        money(r["acp_5yr_usd"]),
        money(r["energy_5yr_usd"]),
        money(r["total_5yr_usd"]),
    ])

# Presentation colors
NAVY = "#203858"
GREEN = "#477E51"
LIGHT_GREEN = "#E6F2E8"
LIGHT_BLUE = "#E8F0F8"
WHITE = "#FFFFFF"
GRAY = "#F5F7F9"

fig, ax = plt.subplots(figsize=(17, 8.5))
fig.patch.set_facecolor(WHITE)
ax.axis("off")

# Title and subtitle
fig.text(
    0.045, 0.95,
    "Farnsworth Street: modeled retrofit costs",
    fontsize=26, fontweight="bold", color=NAVY
)
fig.text(
    0.045, 0.895,
    "BERDO ID 106476  |  2030–2034  |  "
    "Mid installation and energy prices",
    fontsize=14, color="#555555"
)

# Table
table = ax.table(
    cellText=rows,
    colLabels=columns,
    cellLoc="center",
    colLoc="center",
    colWidths=[0.285, 0.11, 0.09, 0.115, 0.12, 0.13, 0.15],
    bbox=[0.035, 0.245, 0.93, 0.62],
)

table.auto_set_font_size(False)
table.set_fontsize(13)

for (i, j), cell in table.get_celld().items():
    cell.set_edgecolor("#DCE2E7")
    cell.set_linewidth(0.5)
    cell.PAD = 0.025

    if i == 0:
        cell.set_facecolor(NAVY)
        cell.get_text().set_color(WHITE)
        cell.get_text().set_weight("bold")
        cell.get_text().set_fontsize(12)
    else:
        r = df.iloc[i - 1]
        total = r["total_5yr_usd"]

        is_overall = abs(total - best_overall) < 1
        is_compliant_best = (
            r["meets_standard"]
            and abs(total - best_compliant) < 1
        )

        if is_overall:
            bg = LIGHT_GREEN
        elif is_compliant_best:
            bg = LIGHT_BLUE
        else:
            bg = WHITE if i % 2 == 0 else GRAY

        cell.set_facecolor(bg)

        if is_overall or is_compliant_best:
            cell.get_text().set_weight("bold")

        if j == 0:
            cell.get_text().set_ha("left")
        elif j >= 3:
            cell.get_text().set_ha("right")

        if j == 6:
            cell.get_text().set_color(NAVY)

# Key takeaway
fig.text(
    0.045, 0.175,
    f"Cheapest overall: {money(best_overall)}"
    f"    |    Cheapest compliant: {money(best_compliant)}"
    f"    |    Compliance premium: {money(premium)}",
    fontsize=16, color=NAVY, fontweight="bold"
)

fig.text(
    0.045, 0.115,
    "Green = lowest-cost overall option     "
    "Blue = lowest-cost compliant option(s)",
    fontsize=12, color=GREEN
)

fig.text(
    0.045, 0.068,
    "HP = heat pump. Costs include installation, "
    "energy bills, and Alternative Compliance Payments. "
    "GHG values are modeled estimates.",
    fontsize=10, color="#666666"
)

# Export
for ext in ["png", "svg"]:
    path = OUT / f"farnsworth_retrofit_comparison.{ext}"
    fig.savefig(
        path,
        dpi=300,
        bbox_inches="tight",
        facecolor=WHITE
    )
    print(f"Saved: {path}")

plt.close(fig)
