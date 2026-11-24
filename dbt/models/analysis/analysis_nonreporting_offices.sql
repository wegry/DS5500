-- The offices left out of the analysis because they report no GHG emissions, compared with
-- the var("match_property_types") offices analyzed (int_berdo_match_buildings). Where a left-
-- out office reports energy use, its emissions intensity is estimated from that use at the
-- median emissions factor of each fuel among the analyzed offices (district cooling falls
-- back to a quarter of electricity's, as in the leave-one-out check). The same estimate for
-- the analyzed offices checks it against their reported intensity. Counts over the limit use
-- today's grid factor and the var("decision_period_start") office standard, as the 99
-- analyzed offices over it do. Writes analysis_outputs/nonreporting_offices.csv.
-- Grain: analyzed offices, plus one row per BERDO compliance status of the left-out ones.
{{ config(post_hook="{{ export_csv('nonreporting_offices.csv', 'analyzed desc, offices desc') }}") }}

with analyzed as (
    select * from {{ ref('int_berdo_match_buildings') }}
),

factors as (
    select
        median(electricity_ghg_kgco2e / electricity_kwh)
            filter (where electricity_kwh > 0) as electricity,
        median(natural_gas_ghg_kgco2e / natural_gas_kwh)
            filter (where natural_gas_kwh > 0) as natural_gas,
        median(district_heating_ghg_kgco2e / district_heating_kwh)
            filter (where district_heating_kwh > 0) as district_heating,
        median(district_cooling_ghg_kgco2e / district_cooling_kwh)
            filter (where district_cooling_kwh > 0) as district_cooling,
        median(oil_propane_ghg_kgco2e / oil_propane_kwh)
            filter (where oil_propane_kwh > 0) as oil_propane
    from analyzed
),

standard as (
    select standard_kgco2e_sqft as limit_kgco2e_sqft
    from {{ ref('berdo_upgrade_compliance') }}
    where period_start = {{ var("decision_period_start") }} and building_use = 'Office'
    limit 1
),

offices as (
    select
        b.*,
        b.berdo_id in (select berdo_id from analyzed) as analyzed,
        b.electricity_kwh + b.natural_gas_kwh + b.district_heating_kwh
            + b.district_cooling_kwh + b.oil_propane_kwh as fuel_total_kwh
    from {{ ref('stg_berdo__buildings') }} as b
    where b.berdo_id is not null
      and b.property_type in (
        {%- for t in var("match_property_types") %}'{{ t }}'{{ ", " if not loop.last }}{% endfor -%}
      )
),

estimated as (
    select
        o.*,
        s.limit_kgco2e_sqft,
        o.fuel_total_kwh / o.gfa_sqft as eui_kwh_sqft,
        (o.electricity_kwh * f.electricity
            + o.natural_gas_kwh * f.natural_gas
            + o.district_heating_kwh * f.district_heating
            + o.district_cooling_kwh * coalesce(f.district_cooling, f.electricity / 4)
            + o.oil_propane_kwh * f.oil_propane) / o.gfa_sqft as estimated_intensity,
        o.ghg_kgco2e / o.gfa_sqft as reported_intensity
    from offices as o
    cross join factors as f
    cross join standard as s
)

select
    analyzed,
    case when analyzed then 'Analyzed' else emissions_compliance_status end as status,
    count(*) as offices,
    median(gfa_sqft) as median_gfa_sqft,
    count(*) filter (where fuel_total_kwh > 0) as with_energy,
    median(eui_kwh_sqft) filter (where fuel_total_kwh > 0) as median_eui_kwh_sqft,
    median(estimated_intensity) filter (where fuel_total_kwh > 0) as median_estimated_intensity,
    count(*) filter (where fuel_total_kwh > 0 and estimated_intensity > limit_kgco2e_sqft)
        as estimated_over_limit,
    count(*) filter (where reported_intensity > limit_kgco2e_sqft) as reported_over_limit,
    count(*) filter (
        where reported_intensity is not null and fuel_total_kwh > 0
          and (estimated_intensity > limit_kgco2e_sqft) = (reported_intensity > limit_kgco2e_sqft)
    ) as estimate_agrees_with_reported,
    corr(estimated_intensity, reported_intensity) as estimate_reported_correlation
from estimated
group by all
