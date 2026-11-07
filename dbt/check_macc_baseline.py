from pathlib import Path
import duckdb
import pandas as pd

root = Path(__file__).resolve().parent
out = root / "analysis_outputs"
out.mkdir(exist_ok=True)

con = duckdb.connect(str(root / "ds5500.duckdb"), read_only=True)

df = con.execute("""
WITH baseline AS (
    SELECT
        berdo_id,
        projected_ghg_intensity_kgco2e_sqft AS baseline_ghg,
        energy_cost_mid_usd_per_year AS baseline_energy
    FROM berdo_decision_options
    WHERE upgrade_id = 0
      AND NOT meets_standard
),
abatement AS (
    SELECT
        o.berdo_id,
        o.upgrade_id,
        o.upgrade_name,
        o.meets_standard,
        o.total_cost_mid_usd,
        o.installed_cost_mid_usd,

        5.0 * (
            b.baseline_ghg -
            o.projected_ghg_intensity_kgco2e_sqft
        ) * bl.gfa_sqft / 1000.0 AS avoided_tons,

        o.installed_cost_mid_usd
        + 5.0 * (
            o.energy_cost_mid_usd_per_year -
            b.baseline_energy
        ) AS incremental_cost_usd

    FROM berdo_decision_options o
    JOIN baseline b USING (berdo_id)
    JOIN int_berdo_match_buildings bl USING (berdo_id)
    WHERE o.upgrade_id <> 0
      AND o.installed_cost_mid_usd > 0
      AND o.applicable_share > 0
)
SELECT
    *,
    incremental_cost_usd / avoided_tons AS mac_usd_per_ton
FROM abatement
WHERE avoided_tons > 0.001
""").df()

assert not df.empty, "No positive-abatement retrofit options found."

# Lowest MAC for each building, regardless of compliance
macc_best = (
    df.sort_values(["berdo_id", "mac_usd_per_ton", "upgrade_id"])
    .drop_duplicates("berdo_id")
)

# Fairer comparison: consider only options meeting the standard
compliant = df[df.meets_standard].copy()

macc_compliant = (
    compliant.sort_values(
        ["berdo_id", "mac_usd_per_ton", "upgrade_id"]
    )
    .drop_duplicates("berdo_id")
)

cost_compliant = (
    compliant.sort_values(
        ["berdo_id", "total_cost_mid_usd", "upgrade_id"]
    )
    .drop_duplicates("berdo_id")
)

comparison = macc_compliant[
    ["berdo_id", "upgrade_id", "total_cost_mid_usd"]
].rename(columns={
    "upgrade_id": "macc_upgrade",
    "total_cost_mid_usd": "macc_total_cost"
}).merge(
    cost_compliant[
        ["berdo_id", "upgrade_id", "total_cost_mid_usd"]
    ].rename(columns={
        "upgrade_id": "optimizer_upgrade",
        "total_cost_mid_usd": "optimizer_total_cost"
    }),
    on="berdo_id"
)

comparison["extra_cost_usd"] = (
    comparison.macc_total_cost -
    comparison.optimizer_total_cost
)

print("\nMACC BASELINE — 5-YEAR OWNER MODEL")
print("Buildings in cohort:", 99)
print("Buildings with positive-abatement options:", len(macc_best))
print("Lowest-MAC option meets standard:",
      int(macc_best.meets_standard.sum()))
print("Buildings with compliant options:", len(comparison))
print("Same compliant retrofit selected:",
      int((comparison.macc_upgrade == comparison.optimizer_upgrade).sum()))
print("Additional modeled cost of MACC ranking: $",
      round(comparison.extra_cost_usd.sum()))

print("\nMOST COMMON LOWEST-MAC RETROFITS")
print(
    macc_best.groupby(["upgrade_id", "upgrade_name"])
    .size().sort_values(ascending=False).head(10)
    .to_string()
)

df.to_csv(out / "macc_options.csv", index=False)
comparison.to_csv(out / "macc_vs_optimizer.csv", index=False)

print("\nResults saved to:", out)
con.close()
