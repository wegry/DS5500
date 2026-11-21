-- Each held-out ComStock office's emissions under each upgrade the optimizer offers, as
-- ComStock simulated them (actual) and as predicted from its neighbors (pred), the way
-- berdo_upgrade_scenarios predicts a BERDO building's: per-fuel upgrade / baseline ratios
-- pooled over the neighbors, applied to the held-out model's own baseline use.
-- Every matching configuration is predicted, {unweighted, inverse_distance} x {no district
-- rule, district rule}, at k = 1 .. floor(sqrt(n)) (the usual ceiling for k-nearest
-- neighbors) and k = 'all' (every candidate), plus k = 'type': every other model of the
-- held-out model's ComStock type, unweighted (what knowing only small / medium / large
-- office predicts; weighting and district_rule are null).
-- Emissions use BERDO's per-fuel factors, the median over the matched offices (constant
-- across Boston offices, so errors are in the units of the BERDO projections), at 2025
-- (BERDO data year) factors; *_elec_ghg is the electricity part, which
-- analysis_loo_residuals scales to the decision year.
-- Grain: held-out model x weighting x district_rule x k x upgrade.
{%- set fuels = ["electricity", "natural_gas", "oil_propane", "district_heating", "district_cooling"] %}
with neighbors as (
    select * from {{ ref('analysis_loo_neighbors') }}
),

ks as (
    select range as k_rank, range::varchar as k
    from range(1, (select floor(sqrt(count(distinct held_out_id)))::int + 1 from neighbors))
),

configs as (
    select *
    from (values ('unweighted'), ('inverse_distance')) as w(weighting)
    cross join (values (false), (true)) as r(district_rule)
),

-- the neighbors each configuration pools at each k, with their weights
neighbor_sets as (
    select n.held_out_id, n.neighbor_id, n.distance, c.weighting, c.district_rule, ks.k
    from neighbors as n
    cross join configs as c
    inner join ks
        on case when c.district_rule then n.rank_rule else n.rank_all end <= ks.k_rank

    union all

    select n.held_out_id, n.neighbor_id, n.distance, c.weighting, c.district_rule, 'all'
    from neighbors as n
    cross join configs as c
    where not c.district_rule or n.district_agrees
),

weighted as (
    select
        *,
        case when weighting = 'inverse_distance' then {{ match_weight('inverse_distance', 'distance') }}
            else {{ match_weight('unweighted') }} end as w
    from neighbor_sets
),

upgrades as (
    select distinct upgrade_id from {{ ref('berdo_decision_options') }} where upgrade_id <> 0
),

-- each model's baseline and upgraded use
fuel_use as (
    select
        b.comstock_id,
        b.comstock_type,
        b.gfa_sqft,
        u.upgrade_id,
        {% for f in fuels -%}
        b.{{ f }}_kwh as base_{{ f }},
        u.{{ f }}_kwh as upgrade_{{ f }}{{ "," if not loop.last }}
        {% endfor -%}
    from {{ ref('int_comstock_models') }} as b
    inner join {{ ref('int_comstock_models') }} as u
        on u.comstock_id = b.comstock_id and u.upgrade_id in (select upgrade_id from upgrades)
    where b.upgrade_id = 0
),

pooled as (
    select
        s.held_out_id,
        s.weighting,
        s.district_rule,
        s.k,
        f.upgrade_id,
        {% for f in fuels -%}
        coalesce(sum(s.w * f.upgrade_{{ f }}) / nullif(sum(s.w * f.base_{{ f }}), 0), 1)
            as {{ f }}_ratio{{ "," if not loop.last }}
        {% endfor -%}
    from weighted as s
    inner join fuel_use as f on f.comstock_id = s.neighbor_id
    group by all
),

-- every other model of the held-out model's type: the type's totals less its own use
type_totals as (
    select
        comstock_type,
        upgrade_id,
        {% for f in fuels -%}
        sum(base_{{ f }}) as base_{{ f }},
        sum(upgrade_{{ f }}) as upgrade_{{ f }}{{ "," if not loop.last }}
        {% endfor -%}
    from fuel_use
    where comstock_id in (select held_out_id from neighbors)
    group by all
),

type_pooled as (
    select
        h.comstock_id as held_out_id,
        null::varchar as weighting,
        null::boolean as district_rule,
        'type' as k,
        h.upgrade_id,
        {% for f in fuels -%}
        coalesce((t.upgrade_{{ f }} - h.upgrade_{{ f }}) / nullif(t.base_{{ f }} - h.base_{{ f }}, 0), 1)
            as {{ f }}_ratio{{ "," if not loop.last }}
        {% endfor -%}
    from fuel_use as h
    inner join type_totals as t using (comstock_type, upgrade_id)
    where h.comstock_id in (select held_out_id from neighbors)
),

factors as (
    select
        {% for f in fuels -%}
        median({{ f }}_ghg_kgco2e / {{ f }}_kwh) filter (where {{ f }}_kwh > 0) as {{ f }},
        {% endfor -%}
    from {{ ref('int_berdo_match_buildings') }}
),

-- no matched office reports district cooling; price it like the fuel_prices seed's proxy,
-- as electricity through a chiller with COP 4
ef as (
    select * replace (coalesce(district_cooling, electricity / 4) as district_cooling)
    from factors
)

select
    p.held_out_id,
    p.weighting,
    p.district_rule,
    p.k,
    p.upgrade_id,
    h.comstock_type,
    h.gfa_sqft,
    h.base_district_heating + h.base_district_cooling > 0 as held_out_uses_district,
    {% for f in fuels %}h.base_{{ f }} * ef.{{ f }}{{ " + " if not loop.last }}{% endfor %} as base_ghg,
    {% for f in fuels %}h.upgrade_{{ f }} * ef.{{ f }}{{ " + " if not loop.last }}{% endfor %} as actual_ghg,
    {% for f in fuels %}h.base_{{ f }} * ef.{{ f }} * p.{{ f }}_ratio{{ " + " if not loop.last }}{% endfor %}
        as pred_ghg,
    h.base_electricity * ef.electricity as base_elec_ghg,
    h.upgrade_electricity * ef.electricity as actual_elec_ghg,
    h.base_electricity * ef.electricity * p.electricity_ratio as pred_elec_ghg
from (select * from pooled union all by name select * from type_pooled) as p
inner join fuel_use as h on h.comstock_id = p.held_out_id and h.upgrade_id = p.upgrade_id
cross join ef
