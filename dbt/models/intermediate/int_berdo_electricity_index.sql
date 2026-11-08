-- BERDO's effective electricity emissions factor by year, as an index on 2025 (the BERDO data
-- year): the City's projected grid factor net of the RPS Class I share
-- (berdo_projected_grid_factors; BERDO Policies & Procedures Appendix B and 225 CMR 14.07).
-- A building's reported electricity emissions times the index are those emissions as BERDO
-- will count them that year, assuming its BCCE/REC share stays the same fraction.
-- Grain: one row per year.
with factor as (
    select year, grid_factor_kg_per_mwh * (1 - rps_class_i_pct / 100) as kg_per_mwh
    from {{ ref('berdo_projected_grid_factors') }}
)

select
    f.year,
    f.kg_per_mwh,
    f.kg_per_mwh / f0.kg_per_mwh as electricity_index
from factor as f
cross join (select kg_per_mwh from factor where year = 2025) as f0
