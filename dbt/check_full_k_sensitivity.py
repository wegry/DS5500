"""Five-year decisions for offices over the 2030 limit at k = 1..match_k, each compared with
the project's match_k (the reference). Rebuilds everything downstream of the matches once per
k, then restores the project's defaults. Run from dbt/: uv run python check_full_k_sensitivity.py
"""
from pathlib import Path
import csv
import re
import subprocess
import duckdb

ROOT = Path(__file__).resolve().parent
K_REF = int(re.search(r"^\s*match_k:\s*(\d+)", (ROOT / "dbt_project.yml").read_text(),
                      flags=re.M).group(1))
KS = range(1, K_REF + 1)
OUT = ROOT / "analysis_outputs" / "k_sensitivity" / "data"
OUT.mkdir(parents=True, exist_ok=True)

DECISION_COLS = [
    "berdo_id", "recommended_upgrade_id", "recommended_option",
    "meets_standard", "projected_ghg_intensity_kgco2e_sqft",
    "installed_cost_mid_usd", "period_acp_usd",
    "period_energy_cost_usd", "total_cost_mid_usd",
]
OPTION_COLS = [
    "berdo_id", "upgrade_id", "upgrade_name", "meets_standard",
    "applicable_share", "installed_cost_mid_usd", "capital_charged_mid_usd",
    "existing_hvac_charged_mid_usd", "period_acp_usd", "period_energy_cost_usd",
    "total_cost_mid_usd",
    "projected_ghg_intensity_kgco2e_sqft",
]

def build(k):
    """Rebuild from the matches down at k; None restores the project's defaults."""
    command = ["uv", "run", "dbt", "build", "--profiles-dir", ".",
               "-s", "int_berdo_comstock_matches+"]
    if k is not None:
        command += ["--vars", f"match_k: {k}"]
    log_path = OUT.parent / "logs" / f"full_k_build_{'default' if k is None else f'{k:02}'}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"Building from the matches down for K={k or K_REF} ...", flush=True)
    with log_path.open("w", encoding="utf-8") as logfile:
        p = subprocess.run(command, cwd=ROOT, stdout=logfile,
                           stderr=subprocess.STDOUT, check=False)
    if p.returncode:
        print(log_path.read_text(encoding="utf-8", errors="replace")[-4500:])
        raise RuntimeError(f"K={k} build failed. See {log_path}")
    print(f"K={k}: dbt build passed", flush=True)

def get_rows(con, query):
    cursor = con.execute(query)
    names = [c[0] for c in cursor.description]
    return [dict(zip(names, values)) for values in cursor.fetchall()]

def save_csv(filename, rows, cols):
    with (OUT / filename).open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

all_decisions, all_options = [], []
cohort_ids = None
last_successful_k = None

try:
    for k in KS:
        build(k)
        last_successful_k = k
        con = duckdb.connect(str(ROOT / "ds5500.duckdb"), read_only=True)
        try:
            decisions = get_rows(con, f"""
                SELECT {', '.join('d.' + c for c in DECISION_COLS)}
                FROM berdo_decisions AS d
                WHERE d.meets_standard_without_upgrade = false
                ORDER BY d.berdo_id
            """)
            options = get_rows(con, f"""
                SELECT {', '.join('o.' + c for c in OPTION_COLS)}
                FROM berdo_decision_options AS o
                JOIN berdo_decisions AS d ON o.berdo_id = d.berdo_id
                WHERE d.meets_standard_without_upgrade = false
                ORDER BY o.berdo_id, o.upgrade_id
            """)
            neighbor_counts = con.execute("""
                SELECT count(*) FILTER (WHERE n <> ?) AS invalid
                FROM (
                  SELECT m.berdo_id, count(*) AS n
                  FROM int_berdo_comstock_matches AS m
                  JOIN berdo_decisions AS d ON m.berdo_id = d.berdo_id
                  WHERE d.meets_standard_without_upgrade = false
                  GROUP BY m.berdo_id
                ) AS t
            """, [k]).fetchone()[0]
        finally:
            con.close()

        ids = {r["berdo_id"] for r in decisions}
        if len(decisions) != len(ids) or not ids:
            raise AssertionError(f"K={k}: missing or duplicate offices: {len(decisions)} rows, {len(ids)} unique")
        if cohort_ids is not None and ids != cohort_ids:
            raise AssertionError(f"K={k}: cohort changed")
        if neighbor_counts != 0:
            raise AssertionError(f"K={k}: {neighbor_counts} buildings have wrong neighbor count")
        cohort_ids = ids
        if len({(r["berdo_id"], r["upgrade_id"]) for r in options}) != len(options):
            raise AssertionError(f"K={k}: duplicate building-option pairs")
        for r in options:
            values = (r["capital_charged_mid_usd"], r["existing_hvac_charged_mid_usd"],
                      r["period_acp_usd"], r["period_energy_cost_usd"], r["total_cost_mid_usd"])
            if any(x is None for x in values) or abs(sum(values[:-1]) - values[-1]) > .01:
                raise AssertionError(f"K={k}: invalid total for {r['berdo_id']}/{r['upgrade_id']}")
        all_decisions.extend([{"k":k, **r} for r in decisions])
        all_options.extend([{"k":k, **r} for r in options])
        print(f"   {len(decisions)} offices; {len(options)} available options", flush=True)
except BaseException:
    print("Attempting to restore the project's defaults...", flush=True)
    try:
        build(None)
    except Exception as restore_error:
        print(f"Restoration FAILED: {restore_error}", flush=True)
    raise

by_k = {
    k: {r["berdo_id"]:r for r in all_decisions if r["k"] == k}
    for k in KS
}
reference = by_k[K_REF]
summary, changes = [], []
for k in KS:
    current = by_k[k]
    changed = []
    for bid in sorted(cohort_ids):
        a, b = current[bid], reference[bid]
        if a["recommended_upgrade_id"] != b["recommended_upgrade_id"]:
            changed.append(bid)
            changes.append({
                "k":k, "berdo_id":bid,
                "upgrade_at_k":a["recommended_upgrade_id"],
                "upgrade_at_ref":b["recommended_upgrade_id"],
                "cost_at_k_usd":a["total_cost_mid_usd"],
                "cost_at_ref_usd":b["total_cost_mid_usd"],
                "meets_standard_at_k":a["meets_standard"],
                "meets_standard_at_ref":b["meets_standard"],
            })
    option_rows_at_k = [o for o in all_options if o["k"] == k]
    summary.append({
        "k": k, "offices":len(current),
        "has_compliant_option":len({o["berdo_id"] for o in option_rows_at_k if o["meets_standard"]}),
        "no_upgrade_selected":sum(r["recommended_upgrade_id"] == 0 for r in current.values()),
        "retrofit_selected":sum(r["recommended_upgrade_id"] != 0 for r in current.values()),
        "selected_meets_standard":sum(bool(r["meets_standard"]) for r in current.values()),
        "different_upgrade_vs_ref":len(changed),
        "different_compliance_vs_ref":sum(
            current[bid]["meets_standard"] != reference[bid]["meets_standard"]
            for bid in cohort_ids
        ),
    })
stable_all_k = sum(len({by_k[k][bid]["recommended_upgrade_id"] for k in KS}) == 1 for bid in cohort_ids)
save_csv("full_k_decisions.csv", all_decisions, ["k", *DECISION_COLS])
save_csv("full_k_options.csv", all_options, ["k", *OPTION_COLS])
save_csv("full_k_summary.csv", summary, list(summary[0]))
save_csv("full_k_changes.csv", changes, [
    "k", "berdo_id", "upgrade_at_k", "upgrade_at_ref", "cost_at_k_usd", "cost_at_ref_usd", "meets_standard_at_k", "meets_standard_at_ref"
])
print(f"\nFULL FIVE-YEAR OPTIMIZER K-SENSITIVITY ({len(cohort_ids)} offices)")
print("K | No upgrade | Retrofitted | Has compliant option | Selected compliant | Different choice vs reference k | Different compliance vs reference k")
for r in summary:
    print(f"{r['k']:2} | {r['no_upgrade_selected']:10} | {r['retrofit_selected']:11} | {r['has_compliant_option']:20} | {r['selected_meets_standard']:18} | {r['different_upgrade_vs_ref']:23} | {r['different_compliance_vs_ref']}")
print(f"\nOffices with same recommendation for all K=1..{K_REF}: {stable_all_k}/{len(cohort_ids)}")
print(f"CSV files saved to: {OUT}")
build(None)
print("Database restored to the project's defaults.")