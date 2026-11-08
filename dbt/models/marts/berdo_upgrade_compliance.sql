-- BERDO compliance by period for each matched building under each ComStock upgrade, plus
-- upgrade 0 (no retrofit). Grain: building x upgrade x 5-year standards period.
-- Energy use is held at the disclosed year's level. The electricity part of the emissions
-- follows BERDO's projected electricity factor (int_berdo_electricity_index) at the start of
-- each period, as in berdo_global_cost's check in its first year; the factor keeps falling
-- inside a period, so the excess over a whole period is an upper bound.
with scenarios as (
    select
        sc.berdo_id,
        sc.gfa_sqft,
        sc.upgrade_id,
        sc.upgrade_name,
        sc.is_package,
        sc.is_theoretical,
        sc.projected_ghg_kgco2e,
        bl.electricity_ghg_kgco2e * sc.electricity_ratio as electricity_ghg_kgco2e
    from {{ ref('berdo_upgrade_scenarios') }} as sc
    inner join {{ ref('int_berdo_match_buildings') }} as bl using (berdo_id)

    union all

    select
        berdo_id,
        gfa_sqft,
        0 as upgrade_id,
        'No upgrade' as upgrade_name,
        false as is_package,
        false as is_theoretical,
        ghg_kgco2e as projected_ghg_kgco2e,
        electricity_ghg_kgco2e
    from {{ ref('int_berdo_match_buildings') }}
),

periods as (
    select
        sc.*,
        st.building_use,
        st.period_start,
        st.period_end,
        st.is_compliance_period,
        st.standard_source,
        st.standard_kgco2e_sqft,
        ix.electricity_index,
        -- emissions as BERDO counts them in the period's first year
        sc.projected_ghg_kgco2e - sc.electricity_ghg_kgco2e * (1 - ix.electricity_index)
            as period_ghg_kgco2e
    from scenarios as sc
    inner join {{ ref('int_berdo_building_standards') }} as st using (berdo_id)
    inner join {{ ref('int_berdo_electricity_index') }} as ix on ix.year = st.period_start
)

select
    berdo_id || '-' || upgrade_id || '-' || period_start as compliance_key,
    berdo_id,
    upgrade_id,
    upgrade_name,
    is_package,
    is_theoretical,
    building_use,
    period_start,
    period_end,
    is_compliance_period,
    standard_source,
    standard_kgco2e_sqft,
    electricity_index,
    period_ghg_kgco2e / gfa_sqft as projected_ghg_intensity_kgco2e_sqft,
    period_ghg_kgco2e / gfa_sqft <= standard_kgco2e_sqft as meets_standard,
    greatest(period_ghg_kgco2e - standard_kgco2e_sqft * gfa_sqft, 0) as excess_kgco2e,
    -- annual payment if the excess is covered with Alternative Compliance Payments
    greatest(period_ghg_kgco2e - standard_kgco2e_sqft * gfa_sqft, 0) / 1000
        * {{ var("acp_usd_per_tco2e") }} as acp_usd_per_year
from periods
