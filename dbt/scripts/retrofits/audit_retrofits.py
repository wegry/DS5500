from pathlib import Path
import duckdb
import polars as pl

root = Path(__file__).resolve().parents[2]
con = duckdb.connect(str(root / "ds5500.duckdb"), read_only=True)

# All ComStock upgrades, using office buildings only
performance = con.sql("""
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
""").pl()

# Existing cost mappings, including imputed measures
mapping = con.sql("""
    SELECT
        upgrade_id,
        count(*) AS mapped_components,
        bool_or(btb_measure_id < 0) AS uses_imputation
    FROM comstock_package_components
    GROUP BY upgrade_id
""").pl()

df = (
    performance.join(mapping, on="upgrade_id", how="left")
    .with_columns(
        pl.col("mapped_components").fill_null(0).cast(pl.Int64),
        pl.col("uses_imputation").fill_null(False),
    )
    .with_columns(
        cost_status=pl.when(pl.col("uses_imputation"))
        .then(pl.lit("Mapped (includes imputation)"))
        .when(pl.col("mapped_components") > 0)
        .then(pl.lit("Mapped (BTB)"))
        .otherwise(pl.lit("Needs cost mapping")),
        cost_review_needed=pl.col("mapped_components") == 0,
    )
    .sort(
        ["avg_reduction_pct", "upgrade_id"],
        descending=[True, False],
        nulls_last=True,
    )
)

out = root / "analysis_outputs" / "retrofits" / "retrofit_coverage_audit.csv"
out.parent.mkdir(parents=True, exist_ok=True)
df.write_csv(out)

with pl.Config(
    tbl_rows=-1,
    tbl_cols=-1,
    tbl_width_chars=200,
    fmt_str_lengths=80,
    tbl_hide_dataframe_shape=True,
    tbl_hide_column_data_types=True,
):
    print("Upgrades audited:", df.height)
    print("\nCost mapping summary:")
    print(df.group_by("cost_status").len().sort("cost_status"))

    print("\nTop 15 currently unmapped upgrades:")
    print(
        df.filter(pl.col("cost_review_needed"))
        .select(
            "upgrade_id", "upgrade_name",
            "applicable_pct", "avg_reduction_pct",
        )
        .head(15)
    )

print("\nSaved:", out)
con.close()
