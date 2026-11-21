"""Inputs shared by the Monte Carlo (monte_carlo_20year.py): the dbt build's options and
component costs, per-option fuel use and emissions, and the signed leave-one-out errors that
dbt writes to analysis_outputs/loo_residuals.csv. Loading checks the inputs against dbt's
five-year costs and ranking.
"""

from __future__ import annotations

import csv
import math
from collections import defaultdict

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
               o.period_acp_usd, o.excess_kgco2e, o.energy_cost_low_usd_per_year,
               o.energy_cost_mid_usd_per_year, o.energy_cost_high_usd_per_year,
               o.installed_cost_mid_usd, o.capital_charged_mid_usd, o.five_year_capital,
               o.capital_discount_rate, o.replaces_hvac, o.existing_hvac_charged_mid_usd,
               o.total_cost_mid_usd, o.cost_rank_mid, b.gfa_sqft
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

    # How much of each component's installed cost the period bears, as dbt's
    # berdo_decision_options.five_year_capital sets it (checked against it below).
    methods = {(o['five_year_capital'], o['capital_discount_rate']) for o in options}
    if len(methods) != 1:
        raise ValueError(f"Expected one five_year_capital method, found {methods}")
    method, r = methods.pop()

    def capital_share(lifetime):
        if method == 'annualized':
            return min(1.0, years * r / (1 - (1 + r) ** -lifetime))
        if method == 'straight_line':
            return min(1.0, years / lifetime)
        if method == 'full':
            return 1.0
        raise ValueError(f"Unknown five_year_capital: {method}")

    components = defaultdict(list)
    for c in query(con, """
        SELECT pc.berdo_id, pc.upgrade_id, pc.btb_measure_id,
               pc.installed_cost_low_usd AS low, pc.installed_cost_mid_usd AS mid,
               pc.installed_cost_high_usd AS high, u.lifetime_years
        FROM int_berdo_package_costs pc
        JOIN int_btb_unit_costs u USING (btb_measure_id)
    """):
        if c['btb_measure_id'] is None:
            raise ValueError("Component without a BTB measure ID.")
        c['capital_share'] = capital_share(float(c['lifetime_years']))
        components[c['berdo_id'], c['upgrade_id']].append(c)

    # Options that keep the existing heating/cooling equipment also pay for replacing it
    # like-for-like (dbt's existing_hvac_charged_*; none under 'full'). These are extra
    # components marked existing=True, so their cost is sampled like any other component.
    existing = defaultdict(list)
    for e in query(con, """
        SELECT berdo_id, btb_measure_id, replacement_cost_low_usd AS low,
               replacement_cost_mid_usd AS mid, replacement_cost_high_usd AS high,
               lifetime_years, remaining_years
        FROM int_berdo_existing_hvac ORDER BY berdo_id, btb_measure_id
    """):
        existing[e['berdo_id']].append(e)
    for o in options:
        if not o['replaces_hvac']:
            for e in existing[o['berdo_id']]:
                components[o['berdo_id'], o['upgrade_id']].append(dict(
                    e, existing=True, capital_share=0.0 if method == 'full'
                    else capital_share(float(e['lifetime_years']))))

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
        installed = sum(float(c['mid']) for c in components[key] if not c.get('existing'))
        charged = sum(float(c['mid']) * c['capital_share'] for c in components[key])
        # simulate() recomputes period_acp_usd year by year and checks it with --zero-uncertainty
        total = charged + float(o['period_acp_usd']) + years * float(
            o['energy_cost_mid_usd_per_year'])
        if not math.isclose(installed, float(o['installed_cost_mid_usd']), abs_tol=0.05):
            raise ValueError(f"Installed cost mismatch: {key}")
        if not math.isclose(charged, float(o['capital_charged_mid_usd'])
                            + float(o['existing_hvac_charged_mid_usd']), abs_tol=0.05):
            raise ValueError(f"Capital charged mismatch ({method}): {key}")
        if not math.isclose(total, float(o['total_cost_mid_usd']), abs_tol=0.05):
            raise ValueError(f"Deterministic cost mismatch: {key}")
    for bid, opts in buildings.items():
        # dbt's ranking: cost to the cent, then emissions to 9 decimals, then upgrade ID
        expected = min(opts, key=lambda o: (round(o['total_cost_mid_usd'], 2),
                                            round(o['projected_ghg_intensity_kgco2e_sqft'], 9),
                                            o['upgrade_id']))
        if expected['cost_rank_mid'] != 1 or sum(o['upgrade_id'] == no_upgrade for o in opts) != 1:
            raise ValueError(f"Existing optimizer rank/baseline mismatch: {bid}")

    matched_types = defaultdict(list)
    for row in query(con, """
        -- each matched type counts as much as dbt's pooling weights its models
        SELECT m.berdo_id, cm.comstock_type, SUM(m.match_weight) AS n
        FROM int_berdo_comstock_matches m
        JOIN int_comstock_models cm ON m.comstock_id = cm.comstock_id
                                   AND cm.upgrade_id = ?
        GROUP BY m.berdo_id, cm.comstock_type
        ORDER BY m.berdo_id, cm.comstock_type  -- fixed order, so a seed reproduces its draws""",
               [no_upgrade]):
        matched_types[row['berdo_id']].append((row['comstock_type'], row['n']))
    if set(buildings) != set(matched_types):
        raise ValueError("Matched ComStock types missing for some buildings.")
        # Keep buildings exceeding the 2030 standard without upgrading.
    all_buildings = len(buildings)
    at_risk = {bid for bid, opts in buildings.items() if any(o['upgrade_id'] == no_upgrade 
               and o['projected_ghg_intensity_kgco2e_sqft'] > o['standard_kgco2e_sqft'] for o in opts)}
    if not at_risk:
        raise ValueError("No buildings exceed the standard.")
    buildings = {bid: opts for bid, opts in buildings.items() if bid in at_risk}
    matched_types = {bid: types for bid, types in matched_types.items() if bid in at_risk}
    components = {key: value for key, value in components.items() if key[0] in at_risk}
    print(f"At-risk buildings: {len(buildings)} of {all_buildings}")
    return buildings, components, matched_types, no_upgrade, upgrades, start, end, rate


FUELS = ('electricity', 'natural_gas', 'oil_propane', 'district_heating', 'district_cooling')


def _ratio(scenario, key):
    """A berdo_upgrade_scenarios ratio, 1 where missing (as SQL COALESCE(..., 1))."""
    value = scenario.get(key) if scenario is not None else None
    return float(1.0 if value is None else value)


def load_emissions(con, buildings):
    """Each option's yearly fuel use and emissions at 2025 (BERDO data year) factors, split
    into the electricity part, which BERDO's and the grid's factor indices scale, and the
    rest: {(berdo_id, upgrade_id): (fuel kWh array in FUELS order, electric kg, other kg)}.
    The no-upgrade option's two parts sum to the building's reported emissions."""
    base = {r['berdo_id']: r for r in query(con, 'SELECT * FROM int_berdo_match_buildings')
            if r['berdo_id'] in buildings}
    ratio = {(r['berdo_id'], r['upgrade_id']): r
             for r in query(con, 'SELECT * FROM berdo_upgrade_scenarios')}
    fuel = {}
    for bid, opts in buildings.items():
        bl = base[bid]
        for o in opts:
            sc = ratio.get((bid, o['upgrade_id']))
            use = np.array([float(bl[f + '_kwh']) * _ratio(sc, f + '_ratio') for f in FUELS])
            elec = float(bl['electricity_ghg_kgco2e']) * _ratio(sc, 'electricity_ratio')
            total = float(bl['ghg_kgco2e'] if sc is None or sc.get('projected_ghg_kgco2e') is None
                          else sc['projected_ghg_kgco2e'])
            fuel[bid, o['upgrade_id']] = (use, elec, total - elec)
    return fuel


def load_errors(csv_path, upgrades, year):
    """Signed LOO errors as fractions of the held-out model's 2025-factor baseline, shape
    (models, upgrades, 2): [..., 0] the electricity part, [..., 1] the rest."""
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
            if 'signed_error_elec_frac' not in row:
                raise ValueError("LOO residuals lack the electricity split. Rerun dbt build.")
            models[mid][upgrade] = (float(row['signed_error_elec_frac']),
                                    float(row['signed_error_other_frac']))
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
