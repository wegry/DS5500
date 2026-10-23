-- BERDO x ComStock upgrades. Grain: one row per BERDO building x ComStock upgrade.
-- ComStock is synthetic, so each building borrows the modeled effect of each upgrade from
-- its nearest ComStock models: per fuel, upgrade use / baseline use pooled over the
-- matches. Those ratios are applied to the building's actual BERDO fuel use and per-fuel
-- emissions, so the projection keeps BERDO's own emission factors.
-- A fuel the matched models do not use keeps a ratio of 1 (unchanged); for a building on
-- district steam whose matches burn gas, electrification therefore adds electricity
-- without removing the steam, and the projection is pessimistic.
{%- set fuels = ["electricity", "natural_gas", "oil_propane", "district_heating", "district_cooling"] %}
with ratios as (
    select
        m.berdo_id,
        u.upgrade_id,
        any_value(u.upgrade_name) as upgrade_name,
        count(*) as matched_models,
        avg(u.applicability::int) as applicable_share,
        {% for f in fuels -%}
        coalesce(sum(u.{{ f }}_kwh) / nullif(sum(b.{{ f }}_kwh), 0), 1) as {{ f }}_ratio,
        {% endfor -%}
        avg(u.eui_kwh_sqft / b.eui_kwh_sqft) as comstock_eui_ratio
    from {{ ref('int_berdo_comstock_matches') }} as m
    inner join {{ ref('int_comstock_models') }} as b
        on m.comstock_id = b.comstock_id and b.upgrade_id = 0
    inner join {{ ref('int_comstock_models') }} as u
        on m.comstock_id = u.comstock_id and u.upgrade_id > 0
    group by m.berdo_id, u.upgrade_id
),

projected as (
    select
        bl.berdo_id,
        bl.owner_name,
        bl.building_address,
        bl.property_type,
        bl.gfa_sqft,
        bl.compliance_standard_kgco2e_sqft,
        bl.eui_kwh_sqft as baseline_eui_kwh_sqft,
        bl.ghg_kgco2e as baseline_ghg_kgco2e,
        bl.ghg_intensity_kgco2e_sqft as baseline_ghg_intensity_kgco2e_sqft,
        r.upgrade_id,
        r.upgrade_name,
        r.upgrade_name like 'Package%' as is_package,
        -- ComStock's theoretical bound on HVAC savings, not an installable measure
        r.upgrade_name = 'Ideal Thermal Air Loads' as is_theoretical,
        r.matched_models,
        r.applicable_share,
        {% for f in fuels -%}
        r.{{ f }}_ratio,
        {% endfor -%}
        (
            {% for f in fuels -%}
            bl.{{ f }}_kwh * r.{{ f }}_ratio{{ " +" if not loop.last }}
            {% endfor -%}
        ) / bl.gfa_sqft as projected_eui_kwh_sqft,
        {% for f in fuels -%}
        bl.{{ f }}_ghg_kgco2e * r.{{ f }}_ratio{{ " +" if not loop.last }}
        {% endfor -%}
            as projected_ghg_kgco2e
    from {{ ref('int_berdo_match_buildings') }} as bl
    inner join ratios as r using (berdo_id)
)

select
    berdo_id || '-' || upgrade_id as scenario_key,
    *,
    projected_ghg_kgco2e / gfa_sqft as projected_ghg_intensity_kgco2e_sqft,
    1 - projected_ghg_kgco2e / baseline_ghg_kgco2e as ghg_reduction_pct,
    baseline_ghg_intensity_kgco2e_sqft <= compliance_standard_kgco2e_sqft as meets_standard_now,
    projected_ghg_kgco2e / gfa_sqft <= compliance_standard_kgco2e_sqft as meets_standard_after
from projected
