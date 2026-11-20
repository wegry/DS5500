"""20-year BERDO Monte Carlo using the existing DuckDB global-cost methodology.

Run from the DS5500 repository root, after `dbt build` and `loo_validation.py`:
    uv run python dbt/monte_carlo_20year.py --zero-uncertainty
    uv run python dbt/monte_carlo_20year.py --draws 2000 --scenarios projected frozen
    uv run python dbt/monte_carlo_20year.py --draws 2000 --scenarios projected \
        --cambium-scenarios MidCase HighRECost HighDemandGrowth

Optional, explicitly *assumed* triangular discount-rate bounds (not sourced probabilities):
    uv run python dbt/monte_carlo_20year.py --draws 2000 \
        --owner-rate-range 0.05 0.09 --societal-rate-range 0.01 0.03

Simulates BTB component installed costs, LOO retrofit-performance errors, and
fuel-price ranges, and evaluates existing AEO/BERDO/Cambium scenario paths.
Discount rates can additionally be sampled if bounds are provided. Emissions
scenarios are evaluated *separately*, not randomly assigned unsupported odds.
Each LOO error is split into an electricity part and the rest (fractions of the
building's 2025-factor emissions); every year, the electricity part scales with
that year's factor index like the emissions it corrects: BERDO's projected
factor for compliance, Cambium's grid for the societal cost, and 1 when
'frozen'. Fuel use is still held at the BERDO year's level, so this remains an
approximation rather than a fully joint fuel/emissions forecast.
Model-conditional, not real-world odds.
"""

from __future__ import annotations

import argparse
import math
import re
from collections import defaultdict
from pathlib import Path

import duckdb
import numpy as np

from monte_carlo import (FUELS, load_emissions, load_errors, load_inputs, query, triangular,
                         write_csv)


PRICE_SERIES = dict(electricity='electricity', natural_gas='natural_gas',
                    oil_propane='distillate', district_heating='natural_gas',
                    district_cooling='electricity')


def project_var(folder, key):
    """Read scalar dbt project vars without requiring a YAML dependency."""
    content = (folder / 'dbt_project.yml').read_text(encoding='utf-8')
    m = re.search(r'^\s*' + re.escape(key) + r':\s*([0-9.]+)\s*(?:#.*)?$',
                  content, flags=re.M)
    if not m:
        raise ValueError(f'Missing numeric dbt var: {key}')
    return float(m.group(1))


def years_from_global_cost(rows):
    """Infer model horizon from its annuity factor."""
    r, a = float(rows[0]['discount_rate']), float(rows[0]['annuity_factor'])
    n = a if abs(r) < 1e-12 else -math.log1p(-a * r) / math.log1p(r)
    if not math.isclose(n, round(n), abs_tol=1e-6) or n <= 0:
        raise ValueError(f'Cannot infer global-cost horizon: {n}')
    return int(round(n))


def load_long_inputs(con, folder, buildings, components, scenarios, cambium_overrides=()):
    options = {(o['berdo_id'], o['upgrade_id']) for opts in buildings.values() for o in opts}
    scenario_rows = {r['scenario']: r for r in query(con, 'SELECT * FROM energy_scenarios')}
    unknown = set(scenarios) - set(scenario_rows)
    if unknown:
        raise ValueError(f'Unknown global-cost scenarios: {sorted(unknown)}')

    rows = query(con, """
        SELECT berdo_id, upgrade_id, scenario, perspective, discount_rate,
               annuity_factor, global_cost_mid_usd, cost_rank_mid
        FROM berdo_global_cost WHERE energy_price = 'mid'""")
    rows = [r for r in rows if r['scenario'] in scenarios]
    if not rows:
        raise ValueError('No matching berdo_global_cost results. Run dbt build.')
    years = years_from_global_cost(rows)
    rates = {}
    expected = {}
    for row in rows:
        key = row['berdo_id'], row['upgrade_id'], row['scenario'], row['perspective']
        if (row['berdo_id'], row['upgrade_id']) in options:
            expected[key] = (float(row['global_cost_mid_usd']), int(row['cost_rank_mid']))
        p = row['perspective']
        if p in rates and not math.isclose(rates[p], float(row['discount_rate'])):
            raise ValueError(f'Inconsistent discount rate for {p}')
        rates[p] = float(row['discount_rate'])
    if set(rates) != {'financial', 'societal'}:
        raise ValueError('Expected financial and societal global-cost perspectives.')
    for scenario in scenarios:
        if sum(k[2] == scenario for k in expected) != 2 * len(options):
            raise ValueError(f'Missing global-cost options for {scenario}')

    # Separate baseline fuel consumption and 2025-reported emissions, then apply
    # the existing ComStock fuel ratios (1 for No upgrade).
    fuel = load_emissions(con, buildings)

    # Published standards for each five-year compliance period.
    baseline_upgrade = next(o['upgrade_id'] for opts in buildings.values()
                            for o in opts if str(o['upgrade_name']).lower().strip() == 'no upgrade')
    standards = defaultdict(dict)
    starts = {o['period_start'] for opts in buildings.values() for o in opts}
    if len(starts) != 1:
        raise ValueError('Expected one common decision year.')
    start = next(iter(starts))
    period_rows = query(con, """
        SELECT berdo_id, period_start, period_end, standard_kgco2e_sqft
        FROM berdo_upgrade_compliance WHERE upgrade_id = ?
    """, [baseline_upgrade])
    for row in period_rows:
        for year in range(max(start, int(row['period_start'])),
                          min(start + years - 1, int(row['period_end'] or start + years - 1)) + 1):
            standards[row['berdo_id']][year] = float(row['standard_kgco2e_sqft'])
    for bid in buildings:
        missing = set(range(start, start + years)) - set(standards[bid])
        if missing:
            raise ValueError(f'No BERDO standard for building {bid}, years {sorted(missing)}')

    f_prices = {r['fuel']: r for r in query(con, 'SELECT * FROM fuel_prices')}
    if set(f_prices) != set(FUELS):
        raise ValueError('Unexpected fuel_prices fuel list.')
    for f in FUELS:
        vals = [float(f_prices[f][f'usd_per_kwh_{c}']) for c in ('low', 'mid', 'high')]
        if vals != sorted(vals) or vals[0] < 0:
            raise ValueError(f'Invalid fuel price range for {f}: {vals}')

    life = {r['btb_measure_id']: float(r['lifetime_years']) for r in query(con,
        'SELECT btb_measure_id, lifetime_years FROM int_btb_unit_costs')}
    for groups in components.values():
        for c in groups:
            if c['btb_measure_id'] not in life or life[c['btb_measure_id']] <= 0:
                raise ValueError(f'Missing equipment lifetime for {c["btb_measure_id"]}')

    berdo = {int(r['year']): (float(r['grid_factor_kg_per_mwh']) *
                                  (1 - float(r['rps_class_i_pct']) / 100))
             for r in query(con, 'SELECT * FROM berdo_projected_grid_factors')}
    cambium = {(r['cambium_scenario'], int(r['year'])): float(r['aer_load_co2e_kg_per_mwh'])
               for r in query(con, 'SELECT * FROM cambium24_isone_aer')}
    aeo = {(r['aeo_case'], r['fuel'], int(r['year'])): float(r['usd2025_per_mmbtu'])
           for r in query(con, 'SELECT * FROM aeo2026_ne_commercial_prices')}

    trajectories = {}
    known_cambium = {name for name, _ in cambium}
    unknown_cambium = set(cambium_overrides) - known_cambium
    if unknown_cambium:
        raise ValueError(f'Unknown Cambium cases: {sorted(unknown_cambium)}')
    for scen in scenarios:
        s = scenario_rows[scen]
        if cambium_overrides and s['cambium_scenario'] is None:
            raise ValueError(f'{scen} has no Cambium pathway to vary; select a projected scenario')
        paths = list(cambium_overrides) if cambium_overrides else [s['cambium_scenario']]
        for cambium_case in paths:
            grid, berdo_ix, prices = [], [], []
            for y in range(start, start + years):
                berdo_ix.append(berdo[y] / berdo[2025] if s['berdo_grid_schedule'] else 1.0)
                cy = cambium_case
                if cy is not None:
                    left = y - y % 5
                    a = cambium[cy, left]
                    b = cambium[cy, left + 5]
                    grid.append((a + (b - a) * (y - left) / 5) / cambium[cy, 2025])
                else:
                    grid.append(1.0)
                case = s['aeo_case']
                ix = []
                for f in FUELS:
                    key = PRICE_SERIES[f]
                    baseline = aeo.get((case, key, 2025)) if case is not None else None
                    current = aeo.get((case, key, y)) if case is not None else None
                    ix.append(current / baseline if baseline and current is not None else 1.0)
                prices.append(ix)
            label = scen if not cambium_overrides else f'{scen}__cambium_{cambium_case}'
            trajectories[label] = (np.asarray(berdo_ix), np.asarray(grid),
                                   np.asarray(prices), scen)
    return (years, start, rates, expected, fuel, standards, f_prices, life,
            trajectories, project_var(folder, 'social_cost_usd_per_tco2e'),
            project_var(folder, 'om_share_per_year'))


def capital_factor(lifetime, horizon, rates):
    """Identical lifetime replacement and terminal residual-value logic to dbt."""
    k = np.arange(math.ceil(horizon / lifetime))
    residual = ((k[-1] + 1) * lifetime - horizon) / lifetime
    return np.power(1 + rates[:, None], -k[None, :] * lifetime).sum(axis=1) - (
        residual * np.power(1 + rates, -horizon))


def rate_draws(rng, base, bounds, n, zero):
    if zero or bounds is None:
        return np.full(n, base)
    lo, hi = bounds
    if not (0 <= lo <= base <= hi):
        raise ValueError(f'Discount range [{lo}, {hi}] must contain existing rate {base}')
    return triangular(rng.random(n), lo, base, hi)


def run_simulation(db, folder, args):
    with duckdb.connect(str(db), read_only=True) as con:
        loaded = load_inputs(con)
        # Keep compatibility with either eight- or nine-field 5-year input helpers.
        if len(loaded) == 9:
            buildings, components, matches, no_upgrade, upgrades, start, _, acp_rate, _ = loaded
        elif len(loaded) == 8:
            buildings, components, matches, no_upgrade, upgrades, start, _, acp_rate = loaded
        else:
            raise ValueError(f'Unexpected load_inputs() return fields: {len(loaded)}')
        (years, start, rates, expected, fuel, standards, price_ranges, lifetimes,
         trajectories, scc, om_share) = load_long_inputs(con, folder, buildings, components,
                                                         args.scenarios, args.cambium_scenarios)
    errors, error_cols, rows_by_type = load_errors(
        folder / 'analysis_outputs' / 'loo_residuals.csv', upgrades, start)
    n = 1 if args.zero_uncertainty else args.draws
    seed = args.seed
    rng = np.random.default_rng(seed)
    # Shared BTB component and fuel-price percentiles across buildings/options.
    technologies = {c['btb_measure_id'] for group in components.values() for c in group}
    cost_u = {t: rng.random(n) for t in sorted(technologies)}
    price_u = rng.random(n)
    drawn_prices = np.stack([
        triangular(price_u,
                   *[float(price_ranges[f][f'usd_per_kwh_{c}']) for c in ('low', 'mid', 'high')])
        for f in FUELS], axis=1) if not args.zero_uncertainty else np.tile(
            [float(price_ranges[f]['usd_per_kwh_mid']) for f in FUELS], (n, 1))
    drawn_rates = {
        'financial': rate_draws(rng, rates['financial'], args.owner_rate_range, n,
                                args.zero_uncertainty),
        'societal': rate_draws(rng, rates['societal'], args.societal_rate_range, n,
                               args.zero_uncertainty),
    }
    t = np.arange(1, years + 1)
    df = {p: np.power(1 + r[:, None], -t[None, :]) for p, r in drawn_rates.items()}
    annuity = {p: ds.sum(axis=1) for p, ds in df.items()}
    cap = {p: {tech: capital_factor(lifetimes[tech], years, drawn_rates[p])
               for tech in technologies} for p in drawn_rates}
    rows_opt, rows_build = [], []

    for bid, opts in sorted(buildings.items()):
        opts = sorted(opts, key=lambda o: o['upgrade_id'])
        option_ids = np.array([o['upgrade_id'] for o in opts])
        gfa = float(opts[0]['gfa_sqft'])
        # reported emissions at 2025 factors, the base the LOO error fractions scale
        baseline_ghg = sum(fuel[bid, no_upgrade][1:])
        st = np.array([standards[bid][year] for year in range(start, start + years)]) * gfa
        # One held-out ComStock model per draw, shared across all upgrade options.
        distribution = matches[bid]
        weights = np.array([cnt for _, cnt in distribution], dtype=float)
        types = rng.choice(len(distribution), n, p=weights / weights.sum())
        selected = np.empty(n, dtype=int)
        for j, (typ, _) in enumerate(distribution):
            mask = (types == j)
            if typ not in rows_by_type:
                raise ValueError(f'Missing LOO residuals for ComStock type {typ}')
            selected[mask] = rng.choice(rows_by_type[typ], mask.sum())
        err = np.zeros_like(errors[selected]) if args.zero_uncertainty else errors[selected]
        orig_installed = {}
        capital = {p: {} for p in rates}
        for o in opts:
            up = o['upgrade_id']
            inst = np.zeros(n)
            cap_by_p = {p: np.zeros(n) for p in rates}
            for c in components.get((bid, up), []):
                tech = c['btb_measure_id']
                sampled = (np.full(n, float(c['mid'])) if args.zero_uncertainty else
                           triangular(cost_u[tech], float(c['low']), float(c['mid']), float(c['high'])))
                inst += sampled
                for p in rates:
                    cap_by_p[p] += sampled * cap[p][tech]
            orig_installed[up] = inst
            for p in rates:
                capital[p][up] = cap_by_p[p]

        for scenario, (berdo_ix, grid_ix, price_ix, base_scenario) in trajectories.items():
            costs_by_p = {p: [] for p in rates}
            compliant = []
            for o in opts:
                up = o['upgrade_id']
                use, electric_ghg, other_ghg = fuel[bid, up]
                # LOO error parts (draws x 1); zero for no upgrade, which is the reported data
                e = (np.zeros((n, 2)) if up == no_upgrade else err[:, error_cols[up]])
                e_elec, e_other = baseline_ghg * e[:, 0:1], baseline_ghg * e[:, 1:2]
                berdo_ghg = np.maximum(0, (electric_ghg + e_elec) * berdo_ix[None, :]
                                       + other_ghg + e_other)
                society_ghg = np.maximum(0, (electric_ghg + e_elec) * grid_ix[None, :]
                                         + other_ghg + e_other)
                annual_energy = (drawn_prices * use[None, :]) @ price_ix.T
                annual_acp = np.maximum(0, berdo_ghg - st[None, :]) * acp_rate
                compliant.append(berdo_ghg <= st[None, :])
                for p in rates:
                    annual_emissions_cost = (annual_acp if p == 'financial' else society_ghg * (scc / 1000))
                    pv = ((annual_energy + annual_emissions_cost) * df[p]).sum(axis=1)
                    pv += capital[p][up] + orig_installed[up] * om_share * annuity[p]
                    costs_by_p[p].append(pv)

            complies = np.stack(compliant, axis=0)
            for p, cost_list in costs_by_p.items():
                costs = np.stack(cost_list, axis=0)
                # dbt global-cost ranking: rounded-to-cent price, then smaller upgrade ID.
                order = np.lexsort((np.broadcast_to(option_ids[:, None], costs.shape),
                                    np.round(costs, 2)), axis=0)
                winner = order[0]
                chosen = [expected[bid, int(up), base_scenario, p] for up in option_ids]
                originally_best = next(i for i, (_, rank) in enumerate(chosen) if rank == 1)
                if args.zero_uncertainty:
                    target = np.array([v[0] for v in chosen])
                    if not np.allclose(costs[:, 0], target, atol=0.05, rtol=0):
                        worst = np.max(np.abs(costs[:, 0] - target))
                        raise ValueError(f'20-year parity mismatch: {bid}, {scenario}, {p}; max ${worst:.2f}')
                    if int(winner[0]) != originally_best:
                        raise ValueError(f'20-year rank mismatch: {bid}, {scenario}, {p}')
                regret = np.maximum(0, costs[originally_best] - costs[winner, np.arange(n)])
                end_compliance = complies[:, :, -1]
                for i, o in enumerate(opts):
                    rows_opt.append(dict(
                        scenario=scenario, perspective=p, berdo_id=bid,
                        upgrade_id=int(option_ids[i]), upgrade_name=o['upgrade_name'],
                        probability_cheapest=round(float((winner == i).mean()), 4),
                        probability_compliant_at_start=round(float(complies[i, :, 0].mean()), 4),
                        probability_compliant_at_end=round(float(end_compliance[i].mean()), 4),
                        mean_global_cost_usd=round(float(costs[i].mean()), 2),
                        p05_global_cost_usd=round(float(np.quantile(costs[i], .05)), 2),
                        p95_global_cost_usd=round(float(np.quantile(costs[i], .95)), 2),
                    ))
                rows_build.append(dict(
                    scenario=scenario, perspective=p, berdo_id=bid,
                    original_upgrade_id=int(option_ids[originally_best]),
                    probability_original_stays_cheapest=round(float((winner == originally_best).mean()), 4),
                    probability_original_compliant_at_start=round(float(complies[originally_best, :, 0].mean()), 4),
                    mean_regret_usd=round(float(regret.mean()), 2),
                    p95_regret_usd=round(float(np.quantile(regret, .95)), 2),
                ))

    summary = []
    for scenario in trajectories:
        for p in rates:
            rows = [r for r in rows_build if r['scenario'] == scenario and r['perspective'] == p]
            summary.append(dict(
                scenario=scenario, perspective=p, start_year=start,
                seed=args.seed,
                end_year=start + years - 1, draws=n, buildings=len(rows),
                assumed_rate_low=(args.owner_rate_range or (rates[p], rates[p]))[0] if p == 'financial'
                    else (args.societal_rate_range or (rates[p], rates[p]))[0],
                assumed_rate_high=(args.owner_rate_range or (rates[p], rates[p]))[1] if p == 'financial'
                    else (args.societal_rate_range or (rates[p], rates[p]))[1],
                mean_recommendation_stability=round(float(np.mean([
                    r['probability_original_stays_cheapest'] for r in rows])), 4),
                total_expected_regret_usd=round(sum(r['mean_regret_usd'] for r in rows), 2),
            ))
    output = folder / 'analysis_outputs' / ('monte_carlo_20yr_zero_check' if args.zero_uncertainty
                                            else 'monte_carlo_20yr')
    output.mkdir(parents=True, exist_ok=True)
    for name, data in [('option_summary.csv', rows_opt), ('building_summary.csv', rows_build),
                       ('cohort_summary.csv', summary)]:
        write_csv(output / name, data)
    print(f'20-year check passed; {len(buildings)} buildings, {n} draws, scenarios={list(trajectories)}')
    print(f'Output: {output}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--draws', type=int, default=2000)
    parser.add_argument('--seed', type=int, default=5500)
    parser.add_argument('--zero-uncertainty', action='store_true')
    parser.add_argument('--scenarios', nargs='+', default=['projected', 'frozen'])
    parser.add_argument('--cambium-scenarios', nargs='+', default=[],
                        help='Optional actual Cambium cases for societal grid-emissions stress tests')
    parser.add_argument('--owner-rate-range', nargs=2, type=float, metavar=('LOW', 'HIGH'))
    parser.add_argument('--societal-rate-range', nargs=2, type=float, metavar=('LOW', 'HIGH'))
    args = parser.parse_args()
    if args.zero_uncertainty and args.cambium_scenarios:
        parser.error('Run zero-uncertainty parity check without Cambium overrides.')
    if args.draws <= 0:
        parser.error('--draws must be positive')
    folder = Path(__file__).resolve().parent
    files = list(folder.glob('*.duckdb'))
    if len(files) != 1:
        parser.error(f'Expected one DuckDB file in {folder}, found {len(files)}')
    run_simulation(files[0], folder, args)


if __name__ == '__main__':
    main()
