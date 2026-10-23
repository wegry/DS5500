-- The var("match_k") nearest ComStock baseline models for each BERDO building, among the
-- ComStock types its property type maps to. Distance: log size gap + log EUI gap + half
-- the L1 gap between fuel shares (the three terms are kept for match-quality checks).
with models as (
    select
        *,
        electricity_kbtu + natural_gas_kbtu + district_heating_kbtu
            + district_cooling_kbtu + oil_propane_kbtu as fuel_total_kbtu
    from {{ ref('int_comstock_models') }}
    where upgrade_id = 0
),

candidates as (
    select
        b.berdo_id,
        m.comstock_id,
        m.comstock_type,
        abs(ln(b.gfa_sqft / m.gfa_sqft)) as size_gap,
        abs(ln(b.eui_kbtu_sqft / m.eui_kbtu_sqft)) as eui_gap,
        0.5 * (
            abs(b.electricity_share - m.electricity_kbtu / m.fuel_total_kbtu)
            + abs(b.natural_gas_share - m.natural_gas_kbtu / m.fuel_total_kbtu)
            + abs(b.district_share
                - (m.district_heating_kbtu + m.district_cooling_kbtu) / m.fuel_total_kbtu)
            + abs(b.oil_propane_share - m.oil_propane_kbtu / m.fuel_total_kbtu)
        ) as fuel_share_gap
    from {{ ref('int_berdo_match_buildings') }} as b
    inner join {{ ref('berdo_comstock_type_crosswalk') }} as cw
        on b.property_type = cw.berdo_type
    inner join models as m
        on cw.comstock_type = m.comstock_type
)

select
    berdo_id || '-' || comstock_id as match_key,
    *,
    size_gap + eui_gap + fuel_share_gap as distance,
    row_number() over (
        partition by berdo_id order by size_gap + eui_gap + fuel_share_gap, comstock_id
    ) as match_rank
from candidates
qualify match_rank <= {{ var("match_k") }}
