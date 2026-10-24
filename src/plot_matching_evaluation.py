
from pathlib import Path

import duckdb
import matplotlib.pyplot as plt

# Project folders
ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "dbt" / "ds5500.duckdb"
OUTPUT = ROOT / "report" / "figures"

OUTPUT.mkdir(parents=True, exist_ok=True)

if not DB_PATH.exists():
    raise FileNotFoundError(f"Database not found: {DB_PATH}")

con = duckdb.connect(str(DB_PATH), read_only=True)


# --------------------------------------------------
# Figure 1: Matching quality by number of neighbors
# --------------------------------------------------

matching_sql = """
WITH neighbor_counts AS (
    SELECT unnest([1, 3, 5, 10]) AS k
),
building_distances AS (
    SELECT
        m.berdo_id,
        n.k,
        avg(m.distance) AS avg_distance
    FROM int_berdo_comstock_matches m
    CROSS JOIN neighbor_counts n
    WHERE m.match_rank <= n.k
    GROUP BY m.berdo_id, n.k
)
SELECT
    k,
    median(avg_distance) AS median_distance,
    quantile_cont(avg_distance, 0.9) AS p90_distance
FROM building_distances
GROUP BY k
ORDER BY k
"""

matching = con.execute(matching_sql).fetchall()

k1 = [r[0] for r in matching]
median_distance = [r[1] for r in matching]
p90_distance = [r[2] for r in matching]

fig, ax = plt.subplots(figsize=(7, 4.5))

ax.plot(k1, median_distance, marker="o", linewidth=2,
        label="Median distance")
ax.plot(k1, p90_distance, marker="s", linewidth=2,
        label="90th percentile")

ax.set_title("BERDO–ComStock Matching Quality")
ax.set_xlabel("Number of nearest ComStock neighbors (k)")
ax.set_ylabel("Average matching distance")
ax.set_xticks(k1)
ax.set_ylim(bottom=0)
ax.grid(alpha=0.25)
ax.legend()

fig.tight_layout()
fig.savefig(OUTPUT / "matching_quality.png", dpi=300)
plt.close(fig)


# --------------------------------------------------
# Figure 2: Emissions prediction sensitivity
# --------------------------------------------------

sensitivity_sql = """
SELECT
    k,
    mean_difference_pp,
    median_difference_pp,
    max_difference_pp,
    compliance_changes,
    affected_buildings
FROM berdo_matching_sensitivity_summary
ORDER BY k
"""

results = con.execute(sensitivity_sql).fetchall()

k2 = [r[0] for r in results]
mean_change = [r[1] for r in results]
median_change = [r[2] for r in results]

fig, ax = plt.subplots(figsize=(7, 4.5))

ax.plot(k2, mean_change, marker="o", linewidth=2,
        label="Mean absolute difference")
ax.plot(k2, median_change, marker="s", linewidth=2,
        label="Median absolute difference")

ax.set_title("Sensitivity of Predicted Emissions Reductions")
ax.set_xlabel("Number of nearest ComStock neighbors (k)")
ax.set_ylabel("Difference from k=10 (percentage points)")
ax.set_xticks(k2)
ax.set_ylim(bottom=0)
ax.grid(alpha=0.25)
ax.legend()

fig.tight_layout()
fig.savefig(OUTPUT / "emissions_sensitivity.png", dpi=300)
plt.close(fig)


# --------------------------------------------------
# Figure 3: BERDO compliance classification changes
# --------------------------------------------------

changes = [r[4] for r in results]
buildings = [r[5] for r in results]

positions = list(range(len(k2)))
width = 0.35

fig, ax = plt.subplots(figsize=(7, 4.5))

bars1 = ax.bar(
    [x - width / 2 for x in positions],
    changes,
    width,
    label="Changed building–upgrade scenarios"
)

bars2 = ax.bar(
    [x + width / 2 for x in positions],
    buildings,
    width,
    label="Distinct affected buildings"
)

ax.bar_label(bars1, padding=3)
ax.bar_label(bars2, padding=3)

ax.set_title("BERDO Compliance Sensitivity")
ax.set_xlabel("Number of nearest ComStock neighbors (k)")
ax.set_ylabel("Count")
ax.set_xticks(positions, [str(k) for k in k2])
ax.set_ylim(0, max(changes + buildings) + 1)
ax.legend()

fig.tight_layout()
fig.savefig(OUTPUT / "compliance_sensitivity.png", dpi=300)
plt.close(fig)

con.close()

print("Three evaluation charts saved to:", OUTPUT)
