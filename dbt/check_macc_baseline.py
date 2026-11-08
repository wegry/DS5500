from pathlib import Path
import duckdb
import polars as pl

root = Path(__file__).resolve().parent
out = root / "analysis_outputs"
out.mkdir(exist_ok=True)

con = duckdb.connect(str(root / "ds5500.duckdb"), read_only=True)

# Buildings that miss the standard with no retrofit
cohort_size = con.sql("""
    SELECT count(*)
    FROM berdo_decision_options
    WHERE upgrade_id = 0 AND NOT meets_standard
""").fetchall()[0][0]

df = con.sql("""
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

        o.period_years * (
            b.baseline_ghg -
            o.projected_ghg_intensity_kgco2e_sqft
        ) * bl.gfa_sqft / 1000.0 AS avoided_tons,

        o.installed_cost_mid_usd
        + o.period_years * (
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
ORDER BY berdo_id, upgrade_id
""").pl()

assert df.height > 0, "No positive-abatement retrofit options found."


def first_per_building(data, by):
    return data.sort(["berdo_id", by, "upgrade_id"]).unique(
        "berdo_id", keep="first", maintain_order=True
    )


# Lowest MAC for each building, regardless of compliance
macc_best = first_per_building(df, "mac_usd_per_ton")

# Fairer comparison: consider only options meeting the standard
compliant = df.filter(pl.col("meets_standard"))

macc_compliant = first_per_building(compliant, "mac_usd_per_ton")
cost_compliant = first_per_building(compliant, "total_cost_mid_usd")

comparison = (
    macc_compliant.select(
        "berdo_id",
        macc_upgrade="upgrade_id",
        macc_total_cost="total_cost_mid_usd",
    )
    .join(
        cost_compliant.select(
            "berdo_id",
            optimizer_upgrade="upgrade_id",
            optimizer_total_cost="total_cost_mid_usd",
        ),
        on="berdo_id",
    )
    .sort("berdo_id")
    .with_columns(
        extra_cost_usd=pl.col("macc_total_cost")
        - pl.col("optimizer_total_cost")
    )
)

same = comparison.filter(
    pl.col("macc_upgrade") == pl.col("optimizer_upgrade")
).height
# Packages 2 and 4 differ only in the RTU heat pump, so in buildings
# without RTUs they are the same retrofit at the same cost; MACC can pick
# either on floating-point noise. Count those as agreeing on cost.
costlier = comparison.filter(pl.col("extra_cost_usd") > 0.01).height

print("\nMACC BASELINE — 5-YEAR OWNER MODEL")
print("Buildings in cohort:", cohort_size)
print("Buildings with positive-abatement options:", macc_best.height)
print("Lowest-MAC option meets standard:",
      macc_best["meets_standard"].sum())
print("Buildings with compliant options:", comparison.height)
print("Same compliant retrofit selected:", same)
print("Different retrofit, same cost:", comparison.height - same - costlier)
print("Different retrofit, higher cost:", costlier)
print("Additional modeled cost of MACC ranking: $",
      round(comparison["extra_cost_usd"].sum()))

print("\nMOST COMMON LOWEST-MAC RETROFITS")
with pl.Config(
    tbl_rows=-1,
    fmt_str_lengths=80,
    tbl_width_chars=200,
    tbl_hide_dataframe_shape=True,
    tbl_hide_column_data_types=True,
):
    print(
        macc_best.group_by("upgrade_id", "upgrade_name")
        .len()
        .sort(["len", "upgrade_id"], descending=[True, False])
        .head(10)
    )

df.write_csv(out / "macc_options.csv")
comparison.write_csv(out / "macc_vs_optimizer.csv")

print("\nResults saved to:", out)
con.close()
