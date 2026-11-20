"""weighted_matching_validation.py's leave-one-out test crossed with the district rule: four
matching configurations, {unweighted, inverse_distance} x {no rule, district rule}, k = 1..24.
This is the evidence for the project's match_k: 20, match_weighting: inverse_distance and
match_district_rule: true.

Same held-out models, upgrades, emission factors, distance and pooled ratios as
weighted_matching_validation.py. The district rule restricts each held-out model's neighbors
to models that agree with it on using any district energy. Read-only.

Run from dbt/ after `dbt build`: uv run python weighted_district_validation.py
Writes analysis_outputs/weighted_district/summary.csv (MAE by k and configuration, overall and
for district-energy models) and bootstrap.csv (paired bootstrap vs unweighted, no rule).
"""
import csv
import random
from pathlib import Path

import duckdb

DBT = Path(__file__).resolve().parent
OUT = DBT / 'analysis_outputs' / 'weighted_district'
FUELS = ('electricity', 'natural_gas', 'oil_propane', 'district_heating', 'district_cooling')
KMAX, EPS, N_BOOT = 24, 1e-6, 4000
BOOT_KS = (10, 15, 20)
CONFIGS = [('unweighted', False), ('inverse_distance', False),
           ('unweighted', True), ('inverse_distance', True)]
BASE = ('unweighted', False)


def name(method, rule):
    return method + (' + district rule' if rule else '')


def write_csv(path, cols, rows):
    with path.open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(cols)
        w.writerows(rows)


con = duckdb.connect(str(DBT / 'ds5500.duckdb'), read_only=True)
baseline = con.execute("""select distinct upgrade_id from berdo_decision_options
    where lower(trim(upgrade_name)) = 'no upgrade'""").fetchall()[0][0]
upgrades = [r[0] for r in con.execute("""select distinct upgrade_id from berdo_decision_options
    where upgrade_id <> ? order by 1""", [baseline]).fetchall()]
types = [r[0] for r in con.execute("""select distinct cw.comstock_type
    from berdo_comstock_type_crosswalk cw
    join (select distinct property_type from int_berdo_match_buildings) b
      on cw.berdo_type = b.property_type order by 1""").fetchall()]
factors = {f: con.execute(f"""select median({f}_ghg_kgco2e / {f}_kwh)
    from int_berdo_match_buildings where {f}_kwh > 0""").fetchone()[0] for f in FUELS}
if factors['district_cooling'] is None:
    factors['district_cooling'] = factors['electricity'] / 4

con.execute('create temp table selected_types(t varchar)')
con.executemany('insert into selected_types values (?)', [(t,) for t in types])
con.execute('create temp table selected_upgrades(id integer)')
con.executemany('insert into selected_upgrades values (?)', [(int(u),) for u in upgrades])

total = ' + '.join(f'{f}_kwh' for f in FUELS)
fuel_gap = ' + '.join(
    f'abs(h.{f}_kwh / h.fuel_total - c.{f}_kwh / c.fuel_total)'
    for f in ('electricity', 'natural_gas', 'oil_propane')
) + """ + abs((h.district_heating_kwh + h.district_cooling_kwh) / h.fuel_total
              - (c.district_heating_kwh + c.district_cooling_kwh) / c.fuel_total)"""
# rk_all: PR 33's ranking. rk_rule: ranking among neighbors that agree on district energy.
con.execute(f"""
    create temp table neighbors as
    with base as (
        select m.*, ({total}) as fuel_total,
            m.district_heating_kwh + m.district_cooling_kwh > 0 as uses_district
        from int_comstock_models m join selected_types t on m.comstock_type = t.t
        where m.upgrade_id = {int(baseline)} and m.gfa_sqft > 0 and m.eui_kwh_sqft > 0
    ), valid as (select * from base where fuel_total > 0),
    pairs as (
        select h.comstock_id as held_id, c.comstock_id as neighbor_id,
            h.uses_district as held_district, h.uses_district = c.uses_district as agrees,
            abs(ln(h.gfa_sqft / c.gfa_sqft)) + abs(ln(h.eui_kwh_sqft / c.eui_kwh_sqft))
            + 0.5 * ({fuel_gap}) as distance
        from valid h join valid c on h.comstock_id <> c.comstock_id
    ), ranked as (
        select *,
            row_number() over (partition by held_id order by distance, neighbor_id) as rk_all,
            row_number() over (partition by held_id, agrees order by distance, neighbor_id)
                as rk_agree
        from pairs
    )
    select *, case when agrees then rk_agree end as rk_rule from ranked
    where rk_all <= {KMAX} or (agrees and rk_agree <= {KMAX})
""")
short = con.execute(f"""select count(*) from (select held_id from neighbors
    group by 1 having count(*) filter (where rk_all <= {KMAX}) < {KMAX}
        or count(*) filter (where rk_rule <= {KMAX}) < {KMAX})""").fetchone()[0]
if short:
    raise ValueError(f'{short} held-out models have fewer than {KMAX} neighbors')

ratios = ',\n'.join(
    f'coalesce(sum(p.w * u.{f}_kwh) / nullif(sum(p.w * b.{f}_kwh), 0), 1) as ratio_{f}'
    for f in FUELS)
base_ghg = ' + '.join(f'h.{f}_kwh * {float(factors[f])}' for f in FUELS)
actual_ghg = ' + '.join(f'hu.{f}_kwh * {float(factors[f])}' for f in FUELS)
pred_ghg = ' + '.join(f'h.{f}_kwh * {float(factors[f])} * r.ratio_{f}' for f in FUELS)
con.execute(f"""
    create temp table errors as
    with configs as (
        select k, method, rule from range(1, {KMAX + 1}) ks(k)
        cross join (values ('unweighted'), ('inverse_distance')) ms(method)
        cross join (values (false), (true)) rs(rule)
    ), pooled as (
        select n.held_id, n.held_district, n.neighbor_id, c.k, c.method, c.rule,
            case when c.method = 'inverse_distance' then 1.0 / (n.distance + {EPS})
                 else 1.0 end as w
        from neighbors n cross join configs c
        where (not c.rule and n.rk_all <= c.k) or (c.rule and n.rk_rule <= c.k)
    ), r as (
        select p.held_id, any_value(p.held_district) as held_district, u.upgrade_id,
            p.k, p.method, p.rule, {ratios}
        from pooled p
        join int_comstock_models b on b.comstock_id = p.neighbor_id and b.upgrade_id = {int(baseline)}
        join int_comstock_models u on u.comstock_id = p.neighbor_id
        join selected_upgrades su on su.id = u.upgrade_id
        group by p.held_id, u.upgrade_id, p.k, p.method, p.rule
    )
    select r.held_id, r.held_district, r.upgrade_id, r.k, r.method, r.rule,
        100.0 * abs(({actual_ghg}) - ({pred_ghg})) / ({base_ghg}) as err_pp
    from r
    join int_comstock_models h on h.comstock_id = r.held_id and h.upgrade_id = {int(baseline)}
    join int_comstock_models hu on hu.comstock_id = r.held_id and hu.upgrade_id = r.upgrade_id
    where ({base_ghg}) > 0
""")

OUT.mkdir(parents=True, exist_ok=True)
summary = con.execute("""
    select k, method, rule, count(distinct held_id) as held_out_models, count(*) as predictions,
        round(avg(err_pp), 3) as mae_pp, round(median(err_pp), 3) as median_ae_pp,
        round(quantile_cont(err_pp, 0.9), 3) as p90_ae_pp,
        round(avg(err_pp) filter (where held_district), 3) as mae_pp_district_models,
        round(avg(err_pp) filter (where not held_district), 3) as mae_pp_other_models
    from errors group by all order by k, rule, method""")
cols = [d[0] for d in summary.description]
srows = summary.fetchall()
write_csv(OUT / 'summary.csv', cols, srows)

# Paired cluster bootstrap vs PR 33's unweighted/no-rule baseline, one cluster per held-out model
per_model = {}
for h, d, k, m, rule, e in con.execute(f"""
        select held_id, any_value(held_district), k, method, rule, avg(err_pp) from errors
        where k in {BOOT_KS} group by held_id, k, method, rule""").fetchall():
    per_model.setdefault((k, m, rule), {})[h] = (d, e)
rng = random.Random(5500)
brows = []
for k in BOOT_KS:
    ref = per_model[(k, *BASE)]
    for m, rule in CONFIGS[1:]:
        cur = per_model[(k, m, rule)]
        for subset in ('all', 'district'):
            ids = sorted(h for h, (d, _) in ref.items() if subset == 'all' or d)
            diffs = [cur[h][1] - ref[h][1] for h in ids]
            n = len(diffs)
            boots = sorted(sum(diffs[rng.randrange(n)] for _ in range(n)) / n
                           for _ in range(N_BOOT))
            brows.append((k, name(m, rule), subset, n, round(sum(diffs) / n, 4),
                          round(boots[int(0.025 * N_BOOT)], 4),
                          round(boots[int(0.975 * N_BOOT) - 1], 4)))
write_csv(OUT / 'bootstrap.csv', ('k', 'config', 'models', 'n', 'diff_vs_unweighted_pp',
                                  'ci95_low_pp', 'ci95_high_pp'), brows)
con.close()
print('done')
