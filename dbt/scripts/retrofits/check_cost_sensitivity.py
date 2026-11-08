from pathlib import Path
import duckdb
import polars as pl

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "analysis_outputs" / "retrofits"
OUT.mkdir(exist_ok=True)

con = duckdb.connect(str(ROOT / "ds5500.duckdb"), read_only=True)

options = con.sql("""
    SELECT berdo_id, upgrade_id, meets_standard,
           total_cost_mid_usd AS cost,
           projected_ghg_intensity_kgco2e_sqft AS ghg
    FROM berdo_decision_options
    WHERE berdo_id IN (
        SELECT berdo_id
        FROM berdo_decision_options
        WHERE upgrade_id = 0 AND NOT meets_standard
    )
""").pl()

# Components set to None: vary entire installation cost.
# Otherwise: vary only the listed components.
GROUPS = {
    "VRF": ([12], None),
    "Geothermal ground loop": ([29], [-29]),
    "Package 5 full installation": ([58], None),
    "Solar PV": ([46, 65], [-46]),
}


def first_per_building(ranked):
    """{berdo_id: upgrade_id} for the first-ranked row of each building."""
    return dict(
        ranked.unique("berdo_id", keep="first", maintain_order=True)
        .select("berdo_id", "upgrade_id")
        .iter_rows()
    )


def choose(data):
    ranked = data.sort(
        ["berdo_id", "cost", "ghg", "upgrade_id"], nulls_last=True
    )
    overall = first_per_building(ranked)
    compliant = first_per_building(ranked.filter(pl.col("meets_standard")))
    return overall, compliant


def count_changes(old, new):
    return sum(
        old.get(bid, -1) != new.get(bid, -1)
        for bid in old.keys() | new.keys()
    )


baseline_overall, baseline_compliant = choose(options)
results = []

for name, (upgrade_ids, component_ids) in GROUPS.items():
    ids_sql = ",".join(map(str, upgrade_ids))
    component_sql = (
        "AND btb_measure_id IN ("
        + ",".join(map(str, component_ids)) + ")"
        if component_ids is not None else ""
    )

    deltas = con.sql(f"""
        SELECT berdo_id, upgrade_id,
            sum(installed_cost_low_usd
                - installed_cost_mid_usd) AS low_delta,
            sum(installed_cost_high_usd
                - installed_cost_mid_usd) AS high_delta
        FROM int_berdo_package_costs
        WHERE upgrade_id IN ({ids_sql})
          {component_sql}
        GROUP BY berdo_id, upgrade_id
    """).pl()

    base = options.join(
        deltas,
        on=["berdo_id", "upgrade_id"],
        how="left",
        validate="m:1",
    )

    mask = pl.col("upgrade_id").is_in(upgrade_ids)
    selected = base.filter(mask)

    assert selected.height > 0, f"No options found for {name}"
    assert (
        selected.select("low_delta", "high_delta")
        .null_count().sum_horizontal().item() == 0
    ), f"Missing cost deltas for {name}"

    for scenario, delta in [
        ("Low", "low_delta"),
        ("Mid", None),
        ("High", "high_delta"),
    ]:
        data = base
        if delta is not None:
            data = base.with_columns(
                cost=pl.when(mask)
                .then(pl.col("cost") + pl.col(delta))
                .otherwise(pl.col("cost"))
            )

        overall, compliant = choose(data)

        results.append({
            "retrofit": name,
            "scenario": scenario,
            "cheapest_compliant": sum(
                u in upgrade_ids for u in compliant.values()
            ),
            "cheapest_overall": sum(
                u in upgrade_ids for u in overall.values()
            ),
            "compliant_coverage": len(compliant),
            "changed_overall_vs_mid": count_changes(
                baseline_overall, overall
            ),
            "changed_compliant_vs_mid": count_changes(
                baseline_compliant, compliant
            ),
        })

result = pl.DataFrame(results)

print("\nALL RETROFIT COST SENSITIVITIES")
with pl.Config(
    tbl_rows=-1,
    tbl_cols=-1,
    tbl_width_chars=200,
    tbl_hide_dataframe_shape=True,
    tbl_hide_column_data_types=True,
):
    print(result)

result.write_csv(OUT / "retrofit_cost_sensitivity.csv")

con.close()
