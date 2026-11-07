from pathlib import Path
import duckdb
import pandas as pd

root = Path(__file__).resolve().parent
con = duckdb.connect(str(root / "ds5500.duckdb"), read_only=True)

# All ComStock upgrades, using office buildings only
performance = con.execute("""
    WITH baseline AS (
        SELECT comstock_id, ghg_kgco2e
        FROM int_comstock_models
        WHERE upgrade_id = 0
          AND comstock_type IN
              ('SmallOffice', 'MediumOffice', 'LargeOffice')
          AND ghg_kgco2e > 0
    )
    SELECT
        u.upgrade_id,
        any_value(u.upgrade_name) AS upgrade_name,
        count(*) AS office_models,
        count(*) FILTER (WHERE u.applicability) AS applicable_models,
        round(100 * avg(u.applicability::INT), 1) AS applicable_pct,
        round(100 * avg(
            1 - u.ghg_kgco2e / b.ghg_kgco2e
        ), 1) AS avg_reduction_pct,
        round(100 * avg(
            1 - u.ghg_kgco2e / b.ghg_kgco2e
        ) FILTER (WHERE u.applicability), 1)
            AS reduction_when_applicable_pct
    FROM int_comstock_models u
    JOIN baseline b USING (comstock_id)
    WHERE u.upgrade_id BETWEEN 1 AND 65
    GROUP BY u.upgrade_id
""").df()

# Existing cost mappings, including imputed measures
mapping = con.execute("""
    SELECT
        upgrade_id,
        count(*) AS mapped_components,
        bool_or(btb_measure_id < 0) AS uses_imputation
    FROM comstock_package_components
    GROUP BY upgrade_id
""").df()

df = performance.merge(mapping, on="upgrade_id", how="left")

df["mapped_components"] = df["mapped_components"].fillna(0).astype(int)
df["uses_imputation"] = df["uses_imputation"].fillna(False).astype(bool)

df["cost_status"] = df.apply(
    lambda r: (
        "Mapped (includes imputation)"
        if r.uses_imputation
        else "Mapped (BTB)"
        if r.mapped_components > 0
        else "Needs cost mapping"
    ),
    axis=1
)

df["cost_review_needed"] = df["mapped_components"].eq(0)

df = df.sort_values("avg_reduction_pct", ascending=False)

out = root / "analysis_outputs" / "retrofit_coverage_audit.csv"
out.parent.mkdir(parents=True, exist_ok=True)
df.to_csv(out, index=False)

print("Upgrades audited:", len(df))
print("\nCost mapping summary:")
print(df.groupby("cost_status").size().to_string())

print("\nTop 15 currently unmapped upgrades:")
cols = [
    "upgrade_id", "upgrade_name",
    "applicable_pct", "avg_reduction_pct"
]
print(
    df[df.cost_review_needed][cols]
    .head(15)
    .to_string(index=False)
)

print("\nSaved:", out)
con.close()
