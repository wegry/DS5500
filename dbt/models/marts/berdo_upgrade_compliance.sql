-- BERDO compliance by period for each matched building under each ComStock upgrade, plus
-- upgrade 0 (no retrofit). Grain: building x upgrade x 5-year standards period.
-- Emissions are held at the disclosed year's level: BERDO's electricity emissions factor
-- falls as the grid decarbonizes, so later-period excess is an upper bound.
with scenarios as (
    select
        berdo_id,
        gfa_sqft,
        upgrade_id,
        upgrade_name,
        is_package,
        is_theoretical,
        projected_ghg_kgco2e
    from {{ ref('berdo_upgrade_scenarios') }}

    union all

    select
        berdo_id,
        gfa_sqft,
        0 as upgrade_id,
        'No upgrade' as upgrade_name,
        false as is_package,
        false as is_theoretical,
        ghg_kgco2e as projected_ghg_kgco2e
    from {{ ref('int_berdo_match_buildings') }}
)

select
    sc.berdo_id || '-' || sc.upgrade_id || '-' || st.period_start as compliance_key,
    sc.berdo_id,
    sc.upgrade_id,
    sc.upgrade_name,
    sc.is_package,
    sc.is_theoretical,
    st.building_use,
    st.period_start,
    st.period_end,
    st.is_compliance_period,
    st.standard_source,
    st.standard_kgco2e_sqft,
    sc.projected_ghg_kgco2e / sc.gfa_sqft as projected_ghg_intensity_kgco2e_sqft,
    sc.projected_ghg_kgco2e / sc.gfa_sqft <= st.standard_kgco2e_sqft as meets_standard,
    greatest(sc.projected_ghg_kgco2e - st.standard_kgco2e_sqft * sc.gfa_sqft, 0)
        as excess_kgco2e,
    -- annual payment if the excess is covered with Alternative Compliance Payments
    greatest(sc.projected_ghg_kgco2e - st.standard_kgco2e_sqft * sc.gfa_sqft, 0) / 1000
        * {{ var("acp_usd_per_tco2e") }} as acp_usd_per_year
from scenarios as sc
inner join {{ ref('int_berdo_building_standards') }} as st using (berdo_id)
