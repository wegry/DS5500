from pathlib import Path
import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "analysis_outputs"
OUT.mkdir(exist_ok=True)

con = duckdb.connect(str(ROOT / "ds5500.duckdb"), read_only=True)

options = con.execute("""
    SELECT berdo_id, upgrade_id, meets_standard,
           total_cost_mid_usd AS cost,
           projected_ghg_intensity_kgco2e_sqft AS ghg
    FROM berdo_decision_options
    WHERE berdo_id IN (
        SELECT berdo_id
        FROM berdo_decision_options
        WHERE upgrade_id = 0 AND NOT meets_standard
    )
""").df()

# Components set to None: vary entire installation cost.
# Otherwise: vary only the listed components.
GROUPS = {
    "VRF": ([12], None),
    "Geothermal ground loop": ([29], [-29]),
    "Package 5 full installation": ([58], None),
    "Solar PV": ([46, 65], [-46]),
}

def choose(data):
    ranked = data.sort_values(
        ["berdo_id", "cost", "ghg", "upgrade_id"]
    )
    overall = ranked.drop_duplicates("berdo_id").set_index(
        "berdo_id"
    )["upgrade_id"]
    compliant = ranked[ranked.meets_standard].drop_duplicates(
        "berdo_id"
    ).set_index("berdo_id")["upgrade_id"]
    return overall, compliant

def count_changes(old, new):
    ids = old.index.union(new.index)
    return int((
        old.reindex(ids).fillna(-1)
        != new.reindex(ids).fillna(-1)
    ).sum())

baseline_overall, baseline_compliant = choose(options)
results = []

for name, (upgrade_ids, component_ids) in GROUPS.items():
    ids_sql = ",".join(map(str, upgrade_ids))
    component_sql = (
        "AND btb_measure_id IN ("
        + ",".join(map(str, component_ids)) + ")"
        if component_ids is not None else ""
    )

    deltas = con.execute(f"""
        SELECT berdo_id, upgrade_id,
            sum(installed_cost_low_usd
                - installed_cost_mid_usd) AS low_delta,
            sum(installed_cost_high_usd
                - installed_cost_mid_usd) AS high_delta
        FROM int_berdo_package_costs
        WHERE upgrade_id IN ({ids_sql})
          {component_sql}
        GROUP BY berdo_id, upgrade_id
    """).df()

    base = options.merge(
        deltas,
        on=["berdo_id", "upgrade_id"],
        how="left",
        validate="many_to_one",
    )

    mask = base.upgrade_id.isin(upgrade_ids)

    assert mask.any(), f"No options found for {name}"
    assert base.loc[
        mask, ["low_delta", "high_delta"]
    ].notna().all().all(), f"Missing cost deltas for {name}"

    for scenario, delta in [
        ("Low", "low_delta"),
        ("Mid", None),
        ("High", "high_delta"),
    ]:
        data = base.copy()

        if delta is not None:
            data.loc[mask, "cost"] = (
                data.loc[mask, "cost"]
                + data.loc[mask, delta]
            )

        overall, compliant = choose(data)

        results.append({
            "retrofit": name,
            "scenario": scenario,
            "cheapest_compliant": int(
                compliant.isin(upgrade_ids).sum()
            ),
            "cheapest_overall": int(
                overall.isin(upgrade_ids).sum()
            ),
            "compliant_coverage": len(compliant),
            "changed_overall_vs_mid": count_changes(
                baseline_overall, overall
            ),
            "changed_compliant_vs_mid": count_changes(
                baseline_compliant, compliant
            ),
        })

result = pd.DataFrame(results)

print("\nALL RETROFIT COST SENSITIVITIES")
print(result.to_string(index=False))

result.to_csv(
    OUT / "retrofit_cost_sensitivity.csv", index=False
)

con.close()
