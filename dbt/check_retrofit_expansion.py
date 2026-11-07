from pathlib import Path
import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "analysis_outputs"
OUT.mkdir(exist_ok=True)

con = duckdb.connect(str(ROOT / "ds5500.duckdb"), read_only=True)

options = con.execute("""
    SELECT berdo_id, upgrade_id, upgrade_name, meets_standard,
           total_cost_mid_usd AS cost,
           projected_ghg_intensity_kgco2e_sqft AS ghg
    FROM berdo_decision_options
    WHERE berdo_id IN (
        SELECT berdo_id
        FROM berdo_decision_options
        WHERE upgrade_id = 0 AND NOT meets_standard
    )
""").df()

STAGES = [
    ("Original 8", [43, 48, 49, 52, 54, 55, 56, 57]),
    ("+ VRF", [12]),
    ("+ Geothermal", [29]),
    ("+ Package 5", [58]),
    ("+ Solar PV", [46, 65]),
]

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

def difference(old, new):
    ids = old.index.union(new.index)
    return int((
        old.reindex(ids).fillna(-1)
        != new.reindex(ids).fillna(-1)
    ).sum())

included = {0}
previous = None
summary = []
changes = []

for name, added in STAGES:
    included.update(added)
    data = options[options.upgrade_id.isin(included)]
    overall, compliant = choose(data)

    newly = 0
    changed_overall = 0
    changed_compliant = 0

    if previous is not None:
        old_overall, old_compliant = previous
        newly = len(compliant.index.difference(
            old_compliant.index
        ))
        changed_overall = difference(old_overall, overall)
        changed_compliant = difference(old_compliant, compliant)

        for bid in overall.index:
            old_o = int(old_overall.get(bid, -1))
            new_o = int(overall.get(bid, -1))
            old_c = int(old_compliant.get(bid, -1))
            new_c = int(compliant.get(bid, -1))

            if old_o != new_o or old_c != new_c:
                changes.append({
                    "stage": name,
                    "berdo_id": bid,
                    "previous_overall": old_o,
                    "new_overall": new_o,
                    "previous_compliant": old_c,
                    "new_compliant": new_c,
                })

    summary.append({
        "stage": name,
        "options": len(included) - 1,
        "buildings": len(overall),
        "compliant_coverage": len(compliant),
        "newly_covered": newly,
        "changed_overall": changed_overall,
        "changed_compliant": changed_compliant,
        "no_upgrade_cheapest": int((overall == 0).sum()),
    })

    previous = overall, compliant

result = pd.DataFrame(summary)
print("\nRETROFIT EXPANSION")
print(result.to_string(index=False))

result.to_csv(
    OUT / "retrofit_expansion_summary.csv", index=False
)
pd.DataFrame(changes).to_csv(
    OUT / "retrofit_expansion_changes.csv", index=False
)


# Compare the original eight retrofits with all expanded options
# using the 20-year discounted global-cost model.
twenty_year = con.execute("""
WITH cohort AS (
    SELECT berdo_id
    FROM berdo_decision_options
    WHERE upgrade_id = 0 AND NOT meets_standard
),
old_best AS (
    SELECT berdo_id, perspective,
           upgrade_id AS old_upgrade,
           global_cost_mid_usd AS old_cost
    FROM berdo_global_cost
    WHERE energy_price = 'mid'
      AND upgrade_id IN (0, 43, 48, 49, 52, 54, 55, 56, 57)
      AND berdo_id IN (SELECT berdo_id FROM cohort)
    QUALIFY row_number() OVER (
        PARTITION BY berdo_id, perspective
        ORDER BY global_cost_mid_usd, upgrade_id
    ) = 1
),
new_best AS (
    SELECT berdo_id, perspective,
           upgrade_id AS new_upgrade,
           global_cost_mid_usd AS new_cost,
           meets_standard_at_start
    FROM berdo_global_cost
    WHERE energy_price = 'mid'
      AND berdo_id IN (SELECT berdo_id FROM cohort)
    QUALIFY row_number() OVER (
        PARTITION BY berdo_id, perspective
        ORDER BY global_cost_mid_usd, upgrade_id
    ) = 1
)
SELECT
    n.perspective,
    count(*) AS buildings,
    count(*) FILTER (
        WHERE o.old_upgrade <> n.new_upgrade
    ) AS changed_recommendations,
    count(*) FILTER (
        WHERE n.new_upgrade IN (12, 29, 46, 58, 65)
    ) AS new_upgrades_selected,
    count(*) FILTER (
        WHERE n.meets_standard_at_start
    ) AS selected_meet_standard,
    round(sum(o.old_cost - n.new_cost))
        AS modeled_savings_usd,
    count(*) FILTER (
        WHERE n.new_cost > o.old_cost + 0.01
    ) AS unexpected_cost_increases
FROM old_best o
JOIN new_best n USING (berdo_id, perspective)
GROUP BY n.perspective
ORDER BY n.perspective
""").df()

print("\n20-YEAR OPTIMIZER COMPARISON")
print(twenty_year.to_string(index=False))

assert (twenty_year["buildings"] == 99).all()
assert (twenty_year["unexpected_cost_increases"] == 0).all()

twenty_year.to_csv(
    OUT / "retrofit_expansion_20yr.csv", index=False
)

con.close()
