
"""Summarize full K=1 to 10 BERDO optimization experiments.

Run from dbt/: uv run python summarize_full_k_sensitivity.py
Requires the CSVs produced by check_full_k_sensitivity.py.
"""

from __future__ import annotations

import csv
from collections import Counter
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "analysis_outputs" / "k_sensitivity" / "data"
FIGURES = OUT.parent / "figures"
FIGURES.mkdir(parents=True, exist_ok=True)

COST_TOLERANCE_USD = 0.01
EXPECTED_K = list(range(1, 11))


def read_csv(name: str, columns: set[str]) -> list[dict[str, str]]:
    path = OUT / name
    if not path.is_file():
        raise SystemExit(f"Missing {path}. Run check_full_k_sensitivity.py first.")
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        missing = columns - set(reader.fieldnames or ())
        if missing:
            raise SystemExit(f"{path.name} is missing columns: {sorted(missing)}")
        return list(reader)


def as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    v = str(value).strip().lower()
    if v in ("true", "1", "t"):
        return True
    if v in ("false", "0", "f"):
        return False
    raise ValueError(f"Unexpected Boolean value {value!r}")


def csv_write(name: str, rows: list[dict], columns: list[str]) -> Path:
    path = OUT / name
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)
    return path

# Load data
summaries = read_csv("full_k_summary.csv", {
    "k", "offices", "no_upgrade_selected", "retrofit_selected",
    "has_compliant_option", "selected_meets_standard",
    "different_upgrade_vs_k10", "different_compliance_vs_k10",
})
decisions = read_csv("full_k_decisions.csv", {
    "k", "berdo_id", "recommended_upgrade_id", "recommended_option",
    "meets_standard", "total_cost_mid_usd",
})
options = read_csv("full_k_options.csv", {
    "k", "berdo_id", "upgrade_id", "upgrade_name",
    "total_cost_mid_usd", "meets_standard",
})
changes = read_csv("full_k_changes.csv", {
    "k", "berdo_id", "upgrade_at_k", "upgrade_at_k10",
})


# Validate cohort and input data
summary_by_k = {}
for row in summaries:
    k = int(row["k"])
    if k in summary_by_k:
        raise SystemExit(f"Duplicate summary for K={k}")
    summary_by_k[k] = row
if sorted(summary_by_k) != EXPECTED_K:
    raise SystemExit(f"Expected K=1..10; found {sorted(summary_by_k)}")
by_k: dict[int, dict[str, dict]] = {k: {} for k in EXPECTED_K}

for row in decisions:
    k = int(row["k"])
    bid = str(row["berdo_id"])
    if k not in by_k or bid in by_k[k]:
        raise SystemExit(f"Unexpected or duplicate decision: K={k}, BERDO={bid}")
    by_k[k][bid] = row


cohort = set(by_k[10])
if not cohort:
    raise SystemExit("K=10 contains no building decisions")
for k in EXPECTED_K:
    if set(by_k[k]) != cohort:
        raise SystemExit(f"K={k} cohort differs from K=10")
    if len(by_k[k]) != int(summary_by_k[k]["offices"]):
        raise SystemExit(f"K={k} office count doesn't match decision rows")


option_at: dict[tuple[int, str, str], dict] = {}
for row in options:
    key = (int(row["k"]), str(row["berdo_id"]), str(row["upgrade_id"]))
    if key in option_at:
        raise SystemExit(f"Duplicate option: {key}")
    option_at[key] = row


# Check that selected options exist and their costs match.

for k in EXPECTED_K:
    for bid, row in by_k[k].items():
        choice = str(row["recommended_upgrade_id"])
        opt = option_at.get((k, bid, choice))
        if opt is None:
            raise SystemExit(f"K={k}, BERDO={bid}: selected option {choice} is missing")
        difference = abs(float(opt["total_cost_mid_usd"]) - float(row["total_cost_mid_usd"]))
        if difference > COST_TOLERANCE_USD:
            raise SystemExit(f"K={k}, BERDO={bid}: decision cost differs from option cost")


# Recompute recommendation changes

computed_changes = {
    (k, bid)
    for k in EXPECTED_K
    for bid in cohort
    if str(by_k[k][bid]["recommended_upgrade_id"]) != str(by_k[10][bid]["recommended_upgrade_id"])
}
provided_changes = {(int(row["k"]), str(row["berdo_id"])) for row in changes}
if len(provided_changes) != len(changes) or provided_changes != computed_changes:
    raise SystemExit("full_k_changes.csv disagrees with decisions")
for k in EXPECTED_K:
    actual = sum(kk == k for kk, _ in computed_changes)
    reported = int(summary_by_k[k]["different_upgrade_vs_k10"])
    if actual != reported:
        raise SystemExit(f"K={k}: reported changes don't match decisions")


# Classify economic differences

material_by_k = Counter()
tie_by_k = Counter()
unavailable_by_k = Counter()
premium_by_k = Counter()
changed_rows = []

for k, bid in sorted(computed_changes, key=lambda x: (x[0], x[1])):
    now = by_k[k][bid]
    ref = by_k[10][bid]
    u_now = str(now["recommended_upgrade_id"])
    u_ref = str(ref["recommended_upgrade_id"])

    # Compare both alternatives using the same K scenario.
    at_k_reference = option_at.get((k, bid, u_ref))
    current_cost = float(now["total_cost_mid_usd"])
    if at_k_reference is None:
        classification = "K10 option unavailable at this K"
        premium = ""
        unavailable_by_k[k] += 1
    else:
        diff = float(at_k_reference["total_cost_mid_usd"]) - current_cost
        if diff < -COST_TOLERANCE_USD:
            raise SystemExit(
                f"K={k}, BERDO={bid}: selected upgrade costs more than the K=10 alternative. Check ranking."
            )
        if abs(diff) <= COST_TOLERANCE_USD:
            classification = "Equal cost (within $0.01)"
            premium = 0.0
            tie_by_k[k] += 1
        else:
            classification = "Economically different at this K"
            premium = diff
            premium_by_k[k] += diff
            material_by_k[k] += 1

    changed_rows.append({
        "k": k,
        "berdo_id": bid,
        "upgrade_at_k": u_now,
        "upgrade_at_k10": u_ref,
        "classification": classification,
        "k_selected_cost_usd": round(current_cost, 2),
        "k10_upgrade_cost_at_k_usd": (
            "" if at_k_reference is None else round(float(at_k_reference["total_cost_mid_usd"]), 2)
        ),
        "k10_choice_premium_at_k_usd": "" if premium == "" else round(premium, 2),
        "selected_compliant_at_k": as_bool(now["meets_standard"]),
        "selected_compliant_at_k10": as_bool(ref["meets_standard"]),
    })


# Building-level stability

building_rows = []

for bid in sorted(cohort):
    sequence = [str(by_k[k][bid]["recommended_upgrade_id"]) for k in EXPECTED_K]
    distinct = len(set(sequence))
    changed_ks = [k for k in EXPECTED_K if sequence[k - 1] != sequence[-1]]
    compliant_sequence = [as_bool(by_k[k][bid]["meets_standard"]) for k in EXPECTED_K]
    building_rows.append({
        "berdo_id": bid,
        "upgrade_at_k10": sequence[-1],
        "upgrade_name_at_k10": by_k[10][bid]["recommended_option"],
        "stable_upgrade_all_k": distinct == 1,
        "distinct_upgrades_selected": distinct,
        "k_values_changed_vs_k10": ",".join(map(str, changed_ks)),
        "change_count_vs_k10": len(changed_ks),
        "compliance_stable_all_k": len(set(compliant_sequence)) == 1,
        "upgrade_sequence_k1_to_k10": ",".join(sequence),
    })


stable = sum(row["stable_upgrade_all_k"] for row in building_rows)
compliance_stable = sum(row["compliance_stable_all_k"] for row in building_rows)
unique_changed = len({bid for _, bid in computed_changes})
not_stable = sorted(
    (row for row in building_rows if not row["stable_upgrade_all_k"]),
    key=lambda row: (-row["change_count_vs_k10"], -row["distinct_upgrades_selected"], row["berdo_id"]),
)


# Generate report

lines = [
    "FULL K=1..10 FIVE-YEAR OPTIMIZER VALIDATION",
    "=" * 72,
    f"Buildings evaluated at every K: {len(cohort)}",
    f"Same upgrade selected at all 10 K values: {stable}/{len(cohort)} ({stable / len(cohort):.1%})",
    f"Upgrade changes at least once: {len(cohort) - stable}/{len(cohort)}",
    f"Buildings with any difference from K=10: {unique_changed}/{len(cohort)}",
    f"Selected compliance stable across all K: {compliance_stable}/{len(cohort)}",
    "",
    (
        "K  No upgrade  Retrofit  Any compliant option  Selected compliant  "
        "Changed vs K10  Equal cost  Meaningful at K  K10 unavailable  K10 premium at K ($)"
    ),
]

for k in EXPECTED_K:
    row = summary_by_k[k]
    lines.append(
        f"{k:2d} "
        f"{int(row['no_upgrade_selected']):11d} "
        f"{int(row['retrofit_selected']):9d} "
        f"{int(row['has_compliant_option']):21d} "
        f"{int(row['selected_meets_standard']):19d} "
        f"{int(row['different_upgrade_vs_k10']):14d} "
        f"{tie_by_k[k]:11d} "
        f"{material_by_k[k]:15d} "
        f"{unavailable_by_k[k]:16d} "
        f"{premium_by_k[k]:18,.2f}"
    )


lines.extend(["", "RECOMMENDED OPTIONS AT K=10"])
upgrade_counts = Counter(str(row["recommended_upgrade_id"]) for row in by_k[10].values())
upgrade_labels = {
    str(row["recommended_upgrade_id"]): str(row["recommended_option"])
    for row in by_k[10].values()
}
for upgrade_id, count in sorted(upgrade_counts.items(), key=lambda pair: (-pair[1], pair[0])):
    lines.append(f"{upgrade_id}: {upgrade_labels[upgrade_id]} - {count} buildings")

lines.extend([
    "",
    "BUILDINGS WITH UNSTABLE RECOMMENDATIONS",
    "BERDO ID | Changes vs K10 | Distinct upgrades | K10 upgrade | K=1..10 upgrade IDs",
])

for row in not_stable[:25]:
    lines.append(
        f"{row['berdo_id']} | {row['change_count_vs_k10']} | "
        f"{row['distinct_upgrades_selected']} | {row['upgrade_at_k10']} | "
        f"{row['upgrade_sequence_k1_to_k10']}"
    )
if len(not_stable) > 25:
    lines.append(f"... {len(not_stable) - 25} more offices are in full_k_building_stability.csv")
if not not_stable:
    lines.append("No changes in selected upgrade across K=1..10.")

lines.extend([
    "",
    "HOW TO READ THIS",
    "- 'Changed' counts different upgrade IDs, even when costs are nearly identical.",
    "- 'Meaningful at K' means the K10 upgrade is available but costs more than the selected upgrade under the same K.",
    "- 'K10 premium at K' is a scenario-dependent comparison, not observed savings.",
    "- 'K10 unavailable' means a direct same-K cost comparison was not possible.",
    "- K10 is a reference configuration, not verified ground truth.",
    "- Rebuilding changes both modeled emissions and installation costs.",
    "- This is model sensitivity analysis, not validation against observed outcomes.",
])


report_path = OUT.parent / "full_k_report.txt"
report = "\n".join(lines) + "\n"
report_path.write_text(report, encoding="utf-8")
print(report)


# Save diagnostic tables

stability_path = csv_write(
    "full_k_building_stability.csv",
    building_rows,
    list(building_rows[0]),
)
diagnostics_path = csv_write(
    "full_k_change_diagnostics.csv",
    changed_rows,
    [
        "k", "berdo_id", "upgrade_at_k", "upgrade_at_k10",
        "classification", "k_selected_cost_usd",
        "k10_upgrade_cost_at_k_usd", "k10_choice_premium_at_k_usd",
        "selected_compliant_at_k", "selected_compliant_at_k10",
    ],
)


# Figure: recommendation changes

ks = EXPECTED_K
fig, ax = plt.subplots(figsize=(10, 5))
ax.bar(
    [str(k) for k in ks],
    [int(summary_by_k[k]["different_upgrade_vs_k10"]) for k in ks],
)
ax.set(
    title="Five-year optimizer: changes versus K=10",
    xlabel="ComStock neighbors used (K)",
    ylabel="Offices with a different selected upgrade",
)
ax.grid(axis="y", alpha=0.2)
fig.tight_layout()
changed_fig = FIGURES / "full_k_recommendation_changes.png"
fig.savefig(changed_fig, dpi=200)
plt.close(fig)


# Optimizer outcomes

fig, ax = plt.subplots(figsize=(10, 5))
ax.plot(
    ks,
    [int(summary_by_k[k]["no_upgrade_selected"]) for k in ks],
    marker="o",
    label="No retrofit chosen",
)
ax.plot(
    ks,
    [int(summary_by_k[k]["retrofit_selected"]) for k in ks],
    marker="o",
    label="Retrofit chosen",
)
ax.plot(
    ks,
    [int(summary_by_k[k]["has_compliant_option"]) for k in ks],
    marker="o",
    label="At least one compliant option",
)
ax.set(
    title="Five-year model outcomes across K=1..10",
    xlabel="ComStock neighbors used (K)",
    ylabel="Number of offices",
)
ax.set_xticks(ks)
ax.grid(axis="y", alpha=0.2)
ax.legend()
fig.tight_layout()
outcome_fig = FIGURES / "full_k_outcomes_by_k.png"
fig.savefig(outcome_fig, dpi=200)
plt.close(fig)

# Confirmation
print("OUTPUTS")

for path in (report_path, stability_path, diagnostics_path, changed_fig, outcome_fig):
    print(" ", path)
