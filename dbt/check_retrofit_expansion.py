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

con.close()
