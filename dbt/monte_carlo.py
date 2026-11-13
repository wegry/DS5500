"""Monte Carlo uncertainty analysis for the EXISTING 5-year BERDO optimizer.

From the DS5500 root, after `dbt build` and `loo_validation.py`:
    uv run python dbt/monte_carlo.py --zero-uncertainty
    uv run python dbt/monte_carlo.py --draws 5000 --seed 5500

Uses the current DuckDB options, component low/mid/high costs, and signed LOO
errors. Keeps energy bills fixed, as in the original 5-year decision model.
Writes three summaries under dbt/analysis_outputs/monte_carlo/.
This estimates *model-conditional* uncertainty, not verified real-world odds.
"""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path

import duckdb
import numpy as np


def query(con, sql, parameters=None):
    result = con.execute(sql, parameters or [])
    fields = [col[0] for col in result.description]
    return [dict(zip(fields, values)) for values in result.fetchall()]


def triangular(quantile, low, mid, high):
    """Triangular inverse CDF so a BTB technology shares one random draw."""
    if not (0 <= low <= mid <= high):
        raise ValueError(f"Invalid installed cost bounds: {low}, {mid}, {high}")
    if low == high:
        return np.full(quantile.shape, low)
    span = high - low
    threshold = (mid - low) / span
    return np.where(
        quantile < threshold,
        low + np.sqrt(np.maximum(0, quantile * span * (mid - low))),
        high - np.sqrt(np.maximum(0, (1 - quantile) * span * (high - mid))),
    )


def load_inputs(con):
    options = query(con, """
        SELECT o.berdo_id, o.upgrade_id, o.upgrade_name, o.period_start,
               o.period_end, o.period_years, o.standard_kgco2e_sqft,
               o.projected_ghg_intensity_kgco2e_sqft, o.acp_usd_per_year,
               o.excess_kgco2e, o.energy_cost_mid_usd_per_year,
               o.installed_cost_mid_usd, o.total_cost_mid_usd, o.cost_rank_mid,
               b.gfa_sqft
        FROM berdo_decision_options o
        JOIN int_berdo_match_buildings b USING (berdo_id)
        ORDER BY o.berdo_id, o.upgrade_id
    """)
    if not options:
        raise ValueError("No decision options. Run dbt build first.")
    baseline = {o['upgrade_id'] for o in options
                if str(o['upgrade_name']).strip().lower() == 'no upgrade'}
    if len(baseline) != 1:
        raise ValueError("Cannot uniquely identify 'No upgrade' in decision options.")
    no_upgrade = baseline.pop()
    upgrades = {o['upgrade_id'] for o in options if o['upgrade_id'] != no_upgrade}
    periods = {(o['period_start'], o['period_end'], o['period_years']) for o in options}
    if len(periods) != 1:
        raise ValueError("Expected one shared decision period.")
    start, end, years = periods.pop()
    if end - start + 1 != years:
        raise ValueError("Inconsistent period length.")

    components = defaultdict(list)
    for c in query(con, """
        SELECT berdo_id, upgrade_id, btb_measure_id,
               installed_cost_low_usd AS low, installed_cost_mid_usd AS mid,
               installed_cost_high_usd AS high
        FROM int_berdo_package_costs
    """):
        if c['btb_measure_id'] is None:
            raise ValueError("Component without a BTB measure ID.")
        components[c['berdo_id'], c['upgrade_id']].append(c)

    excess_rates = [o['acp_usd_per_year'] / o['excess_kgco2e'] for o in options
                    if o['excess_kgco2e'] > 0]
    if not excess_rates:
        raise ValueError("Cannot infer ACP rate from existing decision options.")
    rate = float(np.median(excess_rates))  # dollars per kg CO2e
    if not np.allclose(excess_rates, rate, rtol=1e-6, atol=1e-7):
        raise ValueError("ACP rates differ across decision options.")

    buildings = defaultdict(list)
    for o in options:
        buildings[o['berdo_id']].append(o)
        key = o['berdo_id'], o['upgrade_id']
        installed = sum(float(c['mid']) for c in components[key])
        intensity = float(o['projected_ghg_intensity_kgco2e_sqft'])
        total = installed + years * (
            max(0, intensity - float(o['standard_kgco2e_sqft']))
            * float(o['gfa_sqft']) * rate + float(o['energy_cost_mid_usd_per_year'])
        )
        if not math.isclose(installed, float(o['installed_cost_mid_usd']), abs_tol=0.05):
            raise ValueError(f"Installed cost mismatch: {key}")
        if not math.isclose(total, float(o['total_cost_mid_usd']), abs_tol=0.05):
            raise ValueError(f"Deterministic cost mismatch: {key}")
    for bid, opts in buildings.items():
        expected = min(opts, key=lambda o: (o['total_cost_mid_usd'],
                                            o['projected_ghg_intensity_kgco2e_sqft'],
                                            o['upgrade_id']))
        if expected['cost_rank_mid'] != 1 or sum(o['upgrade_id'] == no_upgrade for o in opts) != 1:
            raise ValueError(f"Existing optimizer rank/baseline mismatch: {bid}")

    matched_types = defaultdict(list)
    for row in query(con, """
        SELECT m.berdo_id, cm.comstock_type, COUNT(*) AS n
        FROM int_berdo_comstock_matches m
        JOIN int_comstock_models cm ON m.comstock_id = cm.comstock_id
                                   AND cm.upgrade_id = ?
        GROUP BY m.berdo_id, cm.comstock_type
    """, [no_upgrade]):
        matched_types[row['berdo_id']].append((row['comstock_type'], row['n']))
    if set(buildings) != set(matched_types):
        raise ValueError("Matched ComStock types missing for some buildings.")
    return buildings, components, matched_types, no_upgrade, upgrades, start, end, rate


def load_errors(csv_path, upgrades, year):
    models = defaultdict(dict)
    types = {}
    with csv_path.open(newline='', encoding='utf-8-sig') as handle:
        for row in csv.DictReader(handle):
            upgrade = int(row['upgrade_id'])
            if upgrade not in upgrades:
                continue
            if int(row['decision_year']) != year:
                raise ValueError("LOO residual decision year does not match the optimizer.")
            mid = row['held_out_model_id']
            if mid in types and types[mid] != row['comstock_type']:
                raise ValueError(f"Conflicting ComStock type for {mid}.")
            if upgrade in models[mid]:
                raise ValueError(f"Duplicate LOO residual for model {mid}, upgrade {upgrade}.")
            models[mid][upgrade] = float(row['signed_error_pp'])
            types[mid] = row['comstock_type']
    ids, upgrade_ids = sorted(models), sorted(upgrades)
    if not ids or any(set(models[mid]) != upgrades for mid in ids):
        raise ValueError("LOO residuals missing for eligible upgrades. Rerun LOO validation.")
    errors = np.array([[models[mid][up] for up in upgrade_ids] for mid in ids])
    if not np.isfinite(errors).all():
        raise ValueError("LOO residual file contains nonfinite errors.")
    type_rows = {t: np.array([i for i, mid in enumerate(ids) if types[mid] == t])
                 for t in set(types.values())}
    return errors, {up: i for i, up in enumerate(upgrade_ids)}, type_rows


def write_csv(path, rows):
    with path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def simulate(buildings, components, matched_types, baseline_id, errors, error_columns,
             type_rows, rate, draws, seed, zero=False):
    rng = np.random.default_rng(seed)
    # Costs sharing a BTB technology receive the same triangular quantile in each draw.
    technologies = {c['btb_measure_id'] for group in components.values() for c in group}
    shared_cost_draws = {tech: rng.random(draws) for tech in sorted(technologies)}
    options_out, buildings_out = [], []
    x = np.arange(draws)
    for bid, opts in sorted(buildings.items()):
        opts = sorted(opts, key=lambda o: o['upgrade_id'])
        ids = np.array([o['upgrade_id'] for o in opts])
        baseline = next(o for o in opts if o['upgrade_id'] == baseline_id)
        baseline_intensity = float(baseline['projected_ghg_intensity_kgco2e_sqft'])
        area, standard, years = (float(baseline['gfa_sqft']),
                                 float(baseline['standard_kgco2e_sqft']),
                                 int(baseline['period_years']))
        if any(o['gfa_sqft'] != area or o['standard_kgco2e_sqft'] != standard for o in opts):
            raise ValueError(f"Inconsistent building data: {bid}")

        # Sample one held-out ComStock model per draw, retaining its errors across upgrades.
        type_counts = matched_types[bid]
        if not all(t in type_rows for t, _ in type_counts):
            raise ValueError(f"LOO has no errors for a matched office type: {bid}")
        weights = np.array([n for _, n in type_counts], dtype=float)
        choice = rng.choice(len(weights), draws, p=weights / weights.sum())
        model_draw = np.empty(draws, dtype=int)
        for j, (t, _) in enumerate(type_counts):
            hits = choice == j
            model_draw[hits] = rng.choice(type_rows[t], int(hits.sum()))
        err = np.zeros_like(errors[model_draw]) if zero else errors[model_draw]

        costs, emissions, compliant = [], [], []
        for o in opts:
            up = o['upgrade_id']
            installed = np.zeros(draws)
            for c in components.get((bid, up), []):
                installed += (float(c['mid']) if zero else triangular(
                    shared_cost_draws[c['btb_measure_id']],
                    float(c['low']), float(c['mid']), float(c['high'])))
            intensity = np.full(draws, float(o['projected_ghg_intensity_kgco2e_sqft']))
            if up != baseline_id:
                intensity = np.maximum(0, intensity + baseline_intensity
                                       * err[:, error_columns[up]] / 100)
            annual_acp = np.maximum(0, intensity - standard) * area * rate
            costs.append(installed + years * (annual_acp + float(o['energy_cost_mid_usd_per_year'])))
            emissions.append(intensity)
            compliant.append(intensity <= standard)
        costs, emissions, compliant = map(np.stack, (costs, emissions, compliant))
        # Same cost / emissions / upgrade ID tie-break as dbt.
        winner = np.lexsort((np.broadcast_to(ids[:, None], costs.shape), emissions, costs), axis=0)[0]
        compliant_cost = np.where(compliant, costs, np.inf)
        compliant_winner = np.lexsort(
            (np.broadcast_to(ids[:, None], costs.shape), emissions, compliant_cost), axis=0)[0]
        any_compliant = compliant.any(axis=0)
        original = next(i for i, o in enumerate(opts) if o['cost_rank_mid'] == 1)
        if zero and (np.any(winner != original) or not np.allclose(
                costs[:, 0], [o['total_cost_mid_usd'] for o in opts], atol=0.05)):
            raise ValueError(f"Zero-uncertainty check failed for building {bid}")
        regret = np.maximum(0, costs[original] - costs[winner, x])

        for i, o in enumerate(opts):
            options_out.append(dict(
                berdo_id=bid, upgrade_id=o['upgrade_id'], upgrade_name=o['upgrade_name'],
                probability_compliant=round(float(compliant[i].mean()), 4),
                probability_cheapest=round(float((winner == i).mean()), 4),
                probability_cheapest_compliant=round(float(((compliant_winner == i) & any_compliant).mean()), 4),
                mean_total_cost_usd=round(float(costs[i].mean()), 2),
                p05_total_cost_usd=round(float(np.quantile(costs[i], .05)), 2),
                p95_total_cost_usd=round(float(np.quantile(costs[i], .95)), 2),
            ))
        buildings_out.append(dict(
            berdo_id=bid, original_upgrade_id=int(ids[original]),
            probability_original_stays_cheapest=round(float((winner == original).mean()), 4),
            probability_original_compliant=round(float(compliant[original].mean()), 4),
            probability_any_compliant=round(float(any_compliant.mean()), 4),
            mean_regret_usd=round(float(regret.mean()), 2),
            p95_regret_usd=round(float(np.quantile(regret, .95)), 2),
        ))
    summary = [dict(
        start_year=next(iter(buildings.values()))[0]['period_start'],
        end_year=next(iter(buildings.values()))[0]['period_end'],
        buildings=len(buildings), draws=draws, seed=seed,
        mean_recommendation_stability=round(float(np.mean(
            [r['probability_original_stays_cheapest'] for r in buildings_out])), 4),
        mean_probability_original_compliant=round(float(np.mean(
            [r['probability_original_compliant'] for r in buildings_out])), 4),
        sum_mean_regret_usd=round(sum(r['mean_regret_usd'] for r in buildings_out), 2),
    )]
    return options_out, buildings_out, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--draws', type=int, default=2000)
    parser.add_argument('--seed', type=int, default=5500)
    parser.add_argument('--zero-uncertainty', action='store_true')
    args = parser.parse_args()
    if args.draws < 1:
        parser.error('--draws must be positive')
    folder = Path(__file__).resolve().parent
    databases = list(folder.glob('*.duckdb'))
    if len(databases) != 1:
        raise ValueError(f"Expected one *.duckdb file in {folder}, found {len(databases)}")
    with duckdb.connect(str(databases[0]), read_only=True) as con:
        buildings, components, matched_types, baseline_id, upgrades, start, end, rate = load_inputs(con)
    residual_csv = folder / 'analysis_outputs' / 'loo_residuals.csv'
    errors, error_cols, by_type = load_errors(residual_csv, upgrades, start)
    option_rows, building_rows, cohort_rows = simulate(
        buildings, components, matched_types, baseline_id, errors, error_cols,
        by_type, rate, args.draws, args.seed, args.zero_uncertainty)
    out = folder / 'analysis_outputs' / ('monte_carlo_zero_check' if args.zero_uncertainty else 'monte_carlo')
    out.mkdir(parents=True, exist_ok=True)
    for name, rows in [('option_summary.csv', option_rows),
                       ('building_summary.csv', building_rows),
                       ('cohort_summary.csv', cohort_rows)]:
        write_csv(out / name, rows)
    print(f"Validated baseline; {len(buildings)} buildings, {len(upgrades)} upgrades, "
          f"{args.draws} draws, {start}–{end}.")
    print(f"Saved results: {out}")


if __name__ == '__main__':
    main()