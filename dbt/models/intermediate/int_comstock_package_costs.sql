-- Installed cost of each package component for each ComStock model. Per-model sizes are
-- identical across the tracts a model is sampled into, so tracts collapse as in
-- int_comstock_models. Grain: ComStock model x package upgrade x component.
with quantities as (
    select
        comstock_id,
        upgrade_id,
        measure,
        any_value(gfa_sqft) as gfa_sqft,
        bool_or(applicability) as applicability,
        avg(quantity) as quantity,
        any_value(quantity_unit) as quantity_unit
    from {{ ref('stg_comstock__package_measures') }}
    group by comstock_id, upgrade_id, measure
)

select
    q.comstock_id || '-' || c.upgrade_id || '-' || c.measure as comstock_component_key,
    q.comstock_id,
    c.upgrade_id,
    c.package_name,
    c.component,
    c.measure,
    c.btb_measure_id,
    q.gfa_sqft,
    q.applicability,
    q.quantity,
    q.quantity_unit,
    u.cost_unit,
    {% for cost in ["low", "mid", "high"] -%}
    q.quantity * u.unit_cost_{{ cost }}_usd as installed_cost_{{ cost }}_usd{{ "," if not loop.last }}
    {% endfor -%}
from {{ ref('comstock_package_components') }} as c
inner join quantities as q using (upgrade_id, measure)
inner join {{ ref('int_btb_unit_costs') }} as u using (btb_measure_id)
