-- Installed cost of each package component for each matched BERDO building. Like the
-- emissions ratios, costs are pooled over the building's matched ComStock models (total
-- cost / total floor area, so a model the measure skips adds floor area at no cost) and
-- scaled to the building's BERDO floor area. Grain: BERDO building x package x component.
select
    m.berdo_id || '-' || c.upgrade_id || '-' || c.measure as berdo_component_key,
    m.berdo_id,
    c.upgrade_id,
    any_value(c.package_name) as package_name,
    c.component,
    c.measure,
    any_value(c.btb_measure_id) as btb_measure_id,
    count(*) as matched_models,
    avg(c.applicability::int) as applicable_share,
    {% for cost in ["low", "mid", "high"] -%}
    sum(c.installed_cost_{{ cost }}_usd) / sum(c.gfa_sqft) as installed_cost_{{ cost }}_usd_per_sqft,
    sum(c.installed_cost_{{ cost }}_usd) / sum(c.gfa_sqft) * any_value(b.gfa_sqft)
        as installed_cost_{{ cost }}_usd{{ "," if not loop.last }}
    {% endfor -%}
from {{ ref('int_berdo_comstock_matches') }} as m
inner join {{ ref('int_berdo_match_buildings') }} as b using (berdo_id)
inner join {{ ref('int_comstock_package_costs') }} as c using (comstock_id)
group by m.berdo_id, c.upgrade_id, c.component, c.measure
