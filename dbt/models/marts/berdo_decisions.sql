-- The minimum-cost var("decision_period_start") option for each matched BERDO building
-- (a retrofit package or no retrofit + ACPs), at BTB mid costs, with the choice under low
-- and high costs to show whether it depends on the cost estimate.
-- Grain: one row per matched BERDO building.
with best as (
    select * from {{ ref('berdo_decision_options') }} where cost_rank_mid = 1
),

no_upgrade as (
    select berdo_id, total_cost_mid_usd, period_acp_usd, meets_standard
    from {{ ref('berdo_decision_options') }}
    where upgrade_id = 0
),

{% for c in ["low", "high"] -%}
best_{{ c }} as (
    select berdo_id, upgrade_id, upgrade_name
    from {{ ref('berdo_decision_options') }}
    where cost_rank_{{ c }} = 1
){{ "," if not loop.last }}
{% endfor %}

select
    b.berdo_id,
    bl.owner_name,
    bl.building_address,
    bl.property_type,
    bl.gfa_sqft,
    b.period_start,
    b.period_end,
    b.is_compliance_period,
    b.standard_kgco2e_sqft,
    bl.ghg_intensity_kgco2e_sqft as baseline_ghg_intensity_kgco2e_sqft,
    n.meets_standard as meets_standard_without_upgrade,
    b.upgrade_id as recommended_upgrade_id,
    case when b.upgrade_id = 0 then 'No upgrade (ACP only)' else b.upgrade_name end
        as recommended_option,
    b.projected_ghg_intensity_kgco2e_sqft,
    b.meets_standard,
    b.applicable_share,
    b.installed_cost_mid_usd,
    b.period_acp_usd,
    b.total_cost_mid_usd,
    n.total_cost_mid_usd as no_upgrade_total_cost_usd,
    n.total_cost_mid_usd - b.total_cost_mid_usd as savings_vs_no_upgrade_usd,
    lo.upgrade_id as recommended_upgrade_id_low_cost,
    hi.upgrade_id as recommended_upgrade_id_high_cost,
    lo.upgrade_id = b.upgrade_id and hi.upgrade_id = b.upgrade_id as is_robust_to_cost
from best as b
inner join {{ ref('int_berdo_match_buildings') }} as bl using (berdo_id)
inner join no_upgrade as n using (berdo_id)
inner join best_low as lo using (berdo_id)
inner join best_high as hi using (berdo_id)
