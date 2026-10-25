"""BERDO / ComStock / BTB: compliant-retrofit financial sensitivity.

Place this file in DS5500/dbt/ next to the project's .duckdb file, then run:
    python financial_k_sensitivity.py

Read-only DuckDB queries; writes three small CSVs to dbt/analysis_outputs/.
Assumptions: fixed installed cost and applicability across k, 2030–2034 ACP,
no operating energy savings. Compliant retrofits only (no ACP-only option).
"""

from __future__ import annotations

import csv
from pathlib import Path
from statistics import median

import duckdb

K_VALUES = (1, 3, 5, 10)
K_REFERENCE = 10
TIE_USD = 1.00


def write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    project_dir = Path(__file__).resolve().parent
    databases = sorted(project_dir.glob("*.duckdb"))
    if len(databases) != 1:
        raise SystemExit(
            f"Expected exactly one .duckdb file in {project_dir}; "
            f"found {len(databases)}: {[str(p) for p in databases]}"
        )
    database = databases[0]
    print("Database:", database)

    with duckdb.connect(str(database), read_only=True) as con:
        rates = con.execute("""
            SELECT MIN(acp_usd_per_year / excess_kgco2e),
                   MEDIAN(acp_usd_per_year / excess_kgco2e),
                   MAX(acp_usd_per_year / excess_kgco2e)
            FROM berdo_decision_options
            WHERE is_compliance_period AND excess_kgco2e > 0
        """).fetchone()
        if any(rate is None for rate in rates):
            raise ValueError("Could not determine the ACP rate from the existing decision model")
        if max(rates) - min(rates) > 1e-6:
            raise ValueError(f"ACP rates are inconsistent: {rates}. Review assumptions first.")
        acp_rate = rates[1]

        above_limit = {
            int(r[0]) for r in con.execute("""
                SELECT berdo_id
                FROM berdo_decisions
                WHERE is_compliance_period
                  AND baseline_ghg_intensity_kgco2e_sqft > standard_kgco2e_sqft
            """).fetchall()
        }

        data = con.execute("""
            SELECT s.k, s.berdo_id, s.upgrade_id, o.upgrade_name,
                   s.meets_standard_after,
                   o.installed_cost_mid_usd,
                   GREATEST(
                       0,
                       s.projected_ghg_kgco2e - o.standard_kgco2e_sqft * d.gfa_sqft
                   ) * ? * o.period_years AS period_acp_usd
            FROM berdo_matching_k_sensitivity AS s
            JOIN berdo_decision_options AS o
              ON s.berdo_id = o.berdo_id AND s.upgrade_id = o.upgrade_id
            JOIN berdo_decisions AS d
              ON s.berdo_id = d.berdo_id
            WHERE d.is_compliance_period
              AND o.is_compliance_period
              AND d.baseline_ghg_intensity_kgco2e_sqft > d.standard_kgco2e_sqft
              AND s.upgrade_id != 0
              AND o.applicable_share > 0
              AND o.installed_cost_mid_usd IS NOT NULL
        """, [acp_rate]).fetchall()

    # All eligible options, including those that do not achieve compliance.
    all_options: dict[tuple[int, int], list[dict]] = {}
    compliant: dict[tuple[int, int], list[dict]] = {}
    for k, building, upgrade, name, meets, installed, acp in data:
        item = {
            "k": int(k),
            "berdo_id": int(building),
            "upgrade_id": int(upgrade),
            "upgrade_name": str(name),
            "meets_standard": bool(meets),
            "installed_cost_mid_usd": float(installed),
            "period_acp_usd": float(acp),
            "total_cost_mid_usd": float(installed + acp),
        }
        key = (int(k), int(building))
        all_options.setdefault(key, []).append(item)
        if meets:
            compliant.setdefault(key, []).append(item)

    for options in compliant.values():
        options.sort(key=lambda x: (x["total_cost_mid_usd"], x["upgrade_id"]))

    best = {key: candidates[0] for key, candidates in compliant.items()}
    baseline_buildings = {b for (k, b) in best if k == K_REFERENCE}
    print(f"ACP: ${acp_rate:.3f} per excess kg CO2e per year")
    print(f"Buildings above 2030 standard: {len(above_limit)}")
    print(f"Buildings with a compliant candidate (k=10): {len(baseline_buildings)}")

    choice_rows = [
        dict(best[key]) for key in sorted(best)
    ]
    changes: list[dict] = []
    summary: list[dict] = []

    for k in K_VALUES:
        k_buildings = {b for (k0, b) in best if k0 == k}
        if k == K_REFERENCE:
            continue
        common = sorted(k_buildings & baseline_buildings)
        changed_count = 0
        tied_count = 0
        lost_compliance_count = 0
        penalties: list[float] = []
        for building in common:
            new_choice = best[(k, building)]
            old_choice = best[(K_REFERENCE, building)]
            if new_choice["upgrade_id"] == old_choice["upgrade_id"]:
                continue
            changed_count += 1
            old_candidate = next(
                (r for r in compliant[(k, building)]
                 if r["upgrade_id"] == old_choice["upgrade_id"]),
                None,
            )
            lost = old_candidate is None
            gap = None
            tied = False
            if lost:
                lost_compliance_count += 1
            else:
                gap = max(0.0, old_candidate["total_cost_mid_usd"]
                          - new_choice["total_cost_mid_usd"])
                penalties.append(gap)
                tied = gap < TIE_USD
                if tied:
                    tied_count += 1
            changes.append({
                "k": k,
                "berdo_id": building,
                "k10_upgrade_id": old_choice["upgrade_id"],
                "k10_upgrade_name": old_choice["upgrade_name"],
                "k_upgrade_id": new_choice["upgrade_id"],
                "k_upgrade_name": new_choice["upgrade_name"],
                "k10_choice_still_compliant": not lost,
                "extra_cost_to_keep_k10_choice_usd": (
                    round(gap, 2) if gap is not None else ""
                ),
                "effectively_tied_under_1_usd": tied,
            })
        summary.append({
            "k": k,
            "reference_k": K_REFERENCE,
            "compliant_buildings_compared": len(common),
            "compliance_availability_set_changes": len(k_buildings ^ baseline_buildings),
            "different_recommendations": changed_count,
            "effectively_tied_under_1_usd": tied_count,
            "k10_choice_not_compliant": lost_compliance_count,
            "median_extra_cost_usd_excluding_noncompliant": (
                round(median(penalties), 2) if penalties else ""
            ),
            "max_extra_cost_usd_excluding_noncompliant": (
                round(max(penalties), 2) if penalties else ""
            ),
        })

    output_dir = project_dir / "analysis_outputs"
    output_dir.mkdir(exist_ok=True)
    write_csv(output_dir / "financial_k_choices.csv", [
        "k", "berdo_id", "upgrade_id", "upgrade_name", "meets_standard",
        "installed_cost_mid_usd", "period_acp_usd", "total_cost_mid_usd"
    ], choice_rows)
    write_csv(output_dir / "financial_k_changes.csv", [
        "k", "berdo_id", "k10_upgrade_id", "k10_upgrade_name",
        "k_upgrade_id", "k_upgrade_name", "k10_choice_still_compliant",
        "extra_cost_to_keep_k10_choice_usd", "effectively_tied_under_1_usd"
    ], changes)
    write_csv(output_dir / "financial_k_summary.csv", [
        "k", "reference_k", "compliant_buildings_compared",
        "compliance_availability_set_changes", "different_recommendations",
        "effectively_tied_under_1_usd", "k10_choice_not_compliant",
        "median_extra_cost_usd_excluding_noncompliant",
        "max_extra_cost_usd_excluding_noncompliant"
    ], summary)

    print("\n--- SENSITIVITY SUMMARY ---")
    for row in summary:
        print(
            f"k={row['k']} vs 10: {row['different_recommendations']}/"
            f"{row['compliant_buildings_compared']} changed; "
            f"ties={row['effectively_tied_under_1_usd']}, "
            f"k10 no longer compliant={row['k10_choice_not_compliant']}; "
            f"median penalty=${row['median_extra_cost_usd_excluding_noncompliant']:,.2f}; "
            f"max penalty=${row['max_extra_cost_usd_excluding_noncompliant']:,.2f}"
        )
    print("\nSaved CSV files in:", output_dir)
    print("NOTE: Installed costs/applicability fixed across k; operating savings excluded.")


if __name__ == "__main__":
    main()