-- The existing heating and cooling equipment of each matched BERDO building and what replacing
-- it like-for-like would cost: the options that keep it (no retrofit, lighting, envelope, PV)
-- must eventually buy this, which the heat pump, VRF and geothermal options replace instead.
-- Sizes come from the matched ComStock models' heat pump sizes for the same equipment
-- (existing_hvac_like_for_like: an RTU's tons, a boiler's tons x 12,000 Btu/h), pooled as
-- int_berdo_package_costs pools costs (weighted total size / total floor area, scaled to the
-- building), so a model without that equipment adds floor area and no size. Empty when
-- var("like_for_like_hvac") is false. remaining_years is when the 20-year global cost first
-- replaces it (var("existing_hvac_remaining_years"); its age is unknown).
-- Grain: BERDO building x existing component.
with sizes as (
    select
        pm.comstock_id,
        s.measure,
        avg(pm.quantity) * any_value(s.capacity_per_quantity) as capacity,
        any_value(pm.gfa_sqft) as gfa_sqft
    from {{ ref('stg_comstock__package_measures') }} as pm
    inner join {{ ref('existing_hvac_like_for_like') }} as s
        on pm.measure = s.measure and pm.upgrade_id = s.quantity_upgrade_id
    group by pm.comstock_id, s.measure
),

pooled as (
    select
        m.berdo_id,
        s.measure,
        sum(m.match_weight * s.capacity) / nullif(sum(m.match_weight * s.gfa_sqft), 0)
            * any_value(b.gfa_sqft) as capacity
    from {{ ref('int_berdo_comstock_matches') }} as m
    inner join sizes as s using (comstock_id)
    inner join {{ ref('int_berdo_match_buildings') }} as b using (berdo_id)
    group by m.berdo_id, s.measure
)

select
    p.berdo_id || '-' || p.measure as existing_hvac_key,
    p.berdo_id,
    p.measure,
    l.btb_measure_id,
    l.existing_equipment,
    p.capacity,
    u.cost_unit,
    {% for c in ["low", "mid", "high"] -%}
    p.capacity * u.unit_cost_{{ c }}_usd as replacement_cost_{{ c }}_usd,
    {% endfor -%}
    u.lifetime_years,
    {{ var("existing_hvac_remaining_years") }}::double as remaining_years
from pooled as p
inner join {{ ref('existing_hvac_like_for_like') }} as l using (measure)
inner join {{ ref('int_btb_unit_costs') }} as u using (btb_measure_id)
where {{ var("like_for_like_hvac", true) }}
