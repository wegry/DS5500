"""Read-only ComStock leave-one-out test of inverse-distance weighted retrofit transfer.

Run from dbt/: python -m uv run python weighted_matching_validation.py
Outputs analysis_outputs/weighted_matching_summary.csv, weighted_matching_by_upgrade.csv,
and weighted_matching_bootstrap.csv.
Compare against the analysis_loo_* dbt models; this is an independent experiment.
"""
from pathlib import Path
import csv
import random
import duckdb

ROOT = Path(__file__).resolve().parent
FUELS = ('electricity', 'natural_gas', 'oil_propane', 'district_heating', 'district_cooling')
KS = tuple(range(1, 25))
EPS = 1e-6


def write_csv(path, columns, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(columns)
        writer.writerows(rows)


def main():
    con = duckdb.connect(str(ROOT / 'ds5500.duckdb'), read_only=True)
    try:
        baseline_rows = con.execute("""select distinct upgrade_id from berdo_decision_options
            where lower(trim(upgrade_name)) = 'no upgrade'""").fetchall()
        if len(baseline_rows) != 1:
            raise ValueError('Expected exactly one No upgrade baseline')
        baseline = baseline_rows[0][0]
        upgrades = [r[0] for r in con.execute('''select distinct upgrade_id from berdo_decision_options
            where upgrade_id <> ? order by upgrade_id''', [baseline]).fetchall()]
        types = [r[0] for r in con.execute('''select distinct cw.comstock_type
            from berdo_comstock_type_crosswalk cw
            join (select distinct property_type from int_berdo_match_buildings) b
            on cw.berdo_type = b.property_type order by 1''').fetchall()]
        if not upgrades or not types:
            raise ValueError('No eligible upgrades or ComStock types')
        factors = {}
        for fuel in FUELS:
            factors[fuel] = con.execute(f'''select median({fuel}_ghg_kgco2e / {fuel}_kwh)
                from int_berdo_match_buildings where {fuel}_kwh > 0''').fetchone()[0]
        if factors['district_cooling'] is None and factors['electricity'] is not None:
            factors['district_cooling'] = factors['electricity'] / 4
        if any(v is None for v in factors.values()):
            raise ValueError(f'Missing emissions factors: {factors}')
        con.execute('create temp table selected_types(t varchar)')
        con.executemany('insert into selected_types values (?)', [(t,) for t in types])
        con.execute('create temp table selected_upgrades(id integer)')
        con.executemany('insert into selected_upgrades values (?)', [(int(u),) for u in upgrades])
        total = ' + '.join(f'{f}_kwh' for f in FUELS)
        fuel_gap = ' + '.join(
            f'abs(h.{f}_kwh / h.fuel_total - c.{f}_kwh / c.fuel_total)'
            for f in ('electricity', 'natural_gas', 'oil_propane')
        ) + ''' + abs((h.district_heating_kwh + h.district_cooling_kwh) / h.fuel_total
                         - (c.district_heating_kwh + c.district_cooling_kwh) / c.fuel_total)'''
        con.execute(f'''
            create temp table neighbors as
            with base as (
                select m.*, ({total}) as fuel_total
                from int_comstock_models m join selected_types t on m.comstock_type=t.t
                where m.upgrade_id={int(baseline)} and m.gfa_sqft>0 and m.eui_kwh_sqft>0
            ), valid as (select * from base where fuel_total>0),
            pairs as (
                select h.comstock_id as held_id, c.comstock_id as neighbor_id,
                abs(ln(h.gfa_sqft/c.gfa_sqft)) + abs(ln(h.eui_kwh_sqft/c.eui_kwh_sqft))
                + 0.5 * ({fuel_gap}) as distance
                from valid h join valid c on h.comstock_id<>c.comstock_id
            )
            select *, row_number() over (partition by held_id order by distance, neighbor_id) as rk
            from pairs
            qualify rk<=24
        ''')
        count = con.execute('select count(distinct held_id) from neighbors').fetchone()[0]
        if count == 0 or con.execute('select count(*) from (select held_id from neighbors group by 1 having count(*)<24)').fetchone()[0]:
            raise ValueError('Insufficient neighbors for one or more held-out models')
        print(f'Valid held-out ComStock models: {count}; upgrades: {len(upgrades)}')
        # Each neighbor contributes baseline and upgraded energy for the same package.
        joined = f'''from neighbors n
            join int_comstock_models b on b.comstock_id=n.neighbor_id and b.upgrade_id={int(baseline)}
            join int_comstock_models u on u.comstock_id=n.neighbor_id
            join selected_upgrades su on su.id=u.upgrade_id'''
        # Weighted pooled ratio, not an average of individual percentage reductions.
        terms = []
        for f in FUELS:
            terms.append(f'''coalesce(sum(w * u.{f}_kwh)/nullif(sum(w * b.{f}_kwh),0),1) as ratio_{f}''')
        ratios_sql = ',\n'.join(terms)
        base_ghg = ' + '.join(f'h.{f}_kwh * {float(factors[f])}' for f in FUELS)
        actual_ghg = ' + '.join(f'hu.{f}_kwh * {float(factors[f])}' for f in FUELS)
        pred_ghg = ' + '.join(f'h.{f}_kwh * {float(factors[f])} * r.ratio_{f}' for f in FUELS)
        # Evaluate each k and weighting method with identical held-out models and upgrades.
        con.execute(f'''
            create temp table errors as
            with methods as (
                select k, method
                from range(1, 25) as ks(k)
                cross join (values ('unweighted'), ('inverse_distance')) as ms(method)
                        ), pooled as (
                select n.held_id, u.upgrade_id, m.k, m.method,
                case when m.method='inverse_distance' then 1.0/(n.distance+{EPS}) else 1.0 end as w,
                n.neighbor_id
                {joined}
                cross join methods m
                where n.rk<=m.k
            ), ratios as (
                select p.held_id, p.upgrade_id, p.k, p.method,
                {ratios_sql}
                from pooled p
                join int_comstock_models b on b.comstock_id=p.neighbor_id and b.upgrade_id={int(baseline)}
                join int_comstock_models u on u.comstock_id=p.neighbor_id and u.upgrade_id=p.upgrade_id
                group by 1,2,3,4
            ), predictions as (
                select r.*, ({base_ghg}) as baseline_ghg,
                    ({actual_ghg}) as actual_ghg, ({pred_ghg}) as predicted_ghg
                from ratios r
                join int_comstock_models h on h.comstock_id=r.held_id and h.upgrade_id={int(baseline)}
                join int_comstock_models hu on hu.comstock_id=r.held_id and hu.upgrade_id=r.upgrade_id
            )
            select held_id, upgrade_id, k, method,
                100.0 * abs(actual_ghg-predicted_ghg)/baseline_ghg as absolute_error_pp
            from predictions where baseline_ghg>0
        ''')
        summary = con.execute('''select method,k,count(distinct held_id) as held_out_models,
            count(*) as predictions, round(avg(absolute_error_pp),3) as mae_pp,
            round(median(absolute_error_pp),3) as median_ae_pp,
            round(quantile_cont(absolute_error_pp,0.9),3) as p90_ae_pp
            from errors group by 1,2 order by k,method''')
        columns = [d[0] for d in summary.description]
        rows = summary.fetchall()
        out = ROOT/'analysis_outputs'
        write_csv(out/'weighted_matching_summary.csv', columns, rows)
        by_upgrade = con.execute('''select upgrade_id,method,k,count(*) as predictions,
            round(avg(absolute_error_pp),3) as mae_pp
            from errors group by 1,2,3 order by 1,3,2''')
        write_csv(out/'weighted_matching_by_upgrade.csv', [d[0] for d in by_upgrade.description], by_upgrade.fetchall())
        # Paired, cluster-level bootstrap: one cluster per held-out ComStock building.
        # Preserve all upgrade outcomes for a building when resampling.
        paired = con.execute("""
            select w.held_id, w.k,
                   avg(w.absolute_error_pp - u.absolute_error_pp) as mean_diff_pp,
                   count(*) as n_upgrades
            from errors w
            join errors u using (held_id, upgrade_id, k)
            where w.method = 'inverse_distance'
              and u.method = 'unweighted'
              and w.k in (10, 15, 20)
            group by w.held_id, w.k
            order by w.k, w.held_id
        """).fetchall()
        grouped = {k: [] for k in (10, 15, 20)}
        for held_id, k, diff, n_upgrades in paired:
            if n_upgrades != len(upgrades):
                raise ValueError(f'Incomplete upgrade coverage for held-out model {held_id} at k={k}')
            grouped[k].append(float(diff))
        rng = random.Random(5500)
        bootstrap_rows = []
        n_boot = 4000
        for k, diffs in grouped.items():
            if len(diffs) != count:
                raise ValueError(f'Incomplete paired sample at k={k}: {len(diffs)} of {count}')
            n = len(diffs)
            observed = sum(diffs) / n
            samples = sorted(sum(diffs[rng.randrange(n)] for _ in range(n)) / n
                             for _ in range(n_boot))
            lower = samples[int(0.025 * n_boot)]
            upper = samples[int(0.975 * n_boot) - 1]
            bootstrap_rows.append((k, n, n * len(upgrades), round(observed, 4),
                                   round(lower, 4), round(upper, 4)))
        bootstrap_columns = ('k', 'held_out_models', 'paired_predictions',
                             'weighted_minus_unweighted_mae_pp', 'ci95_low_pp', 'ci95_high_pp')
        write_csv(out/'weighted_matching_bootstrap.csv', bootstrap_columns, bootstrap_rows)
        print('Paired bootstrap (negative favors weighting):')
        print(' | '.join(bootstrap_columns))
        for row in bootstrap_rows:
            print(' | '.join(map(str, row)))
        print('Saved analysis_outputs/weighted_matching_bootstrap.csv')
        print(' | '.join(columns))
        for row in rows:
            print(' | '.join(map(str,row)))
        print('Saved analysis_outputs/weighted_matching_summary.csv and weighted_matching_by_upgrade.csv')
    finally:
        con.close()


if __name__ == '__main__':
    main()
