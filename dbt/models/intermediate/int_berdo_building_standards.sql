-- BERDO emissions standard for each building in each 5-year period. Grain: building x period.
-- The disclosed 2025-2029 standard equals the largest use's category standard for ~95% of
-- buildings (blending is rare in practice), so later periods scale the disclosed standard
-- along the largest use's trajectory: exact for single-category buildings, approximate for
-- blended ones. Buildings without a disclosed standard use the category value directly.
with buildings as (
    select
        b.berdo_id,
        b.property_type,
        b.first_compliance_year,
        b.compliance_standard_kgco2e_sqft as disclosed_standard_kgco2e_sqft,
        u.building_use
    from {{ ref('stg_berdo__buildings') }} as b
    left join {{ ref('berdo_property_type_uses') }} as u using (property_type)
    where b.berdo_id is not null
),

first_period as (
    select building_use, standard_kgco2e_sqft as first_standard
    from {{ ref('berdo_emissions_standards') }}
    where period_start = 2025
)

select
    b.berdo_id || '-' || s.period_start as building_period_key,
    b.berdo_id,
    b.property_type,
    b.building_use,
    b.first_compliance_year,
    s.period_start,
    s.period_end,
    coalesce(s.period_end >= b.first_compliance_year, true) as is_compliance_period,
    case
        when b.disclosed_standard_kgco2e_sqft is not null
            then b.disclosed_standard_kgco2e_sqft * s.standard_kgco2e_sqft / f.first_standard
        else s.standard_kgco2e_sqft
    end as standard_kgco2e_sqft,
    case
        when b.disclosed_standard_kgco2e_sqft is not null then 'disclosed_scaled'
        else 'category'
    end as standard_source
from buildings as b
inner join {{ ref('berdo_emissions_standards') }} as s using (building_use)
inner join first_period as f using (building_use)
