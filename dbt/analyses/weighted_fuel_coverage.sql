-- Weighted coverage of fuels reported by matched BERDO office buildings.
-- One row per BERDO office and fuel it uses. No production models are changed.
WITH baseline_neighbors AS (
    SELECT
        m.berdo_id,
        m.comstock_id,
        m.match_weight,
        c.electricity_kwh,
        c.natural_gas_kwh,
        c.oil_propane_kwh,
        c.district_heating_kwh,
        c.district_cooling_kwh
    FROM main.int_berdo_comstock_matches AS m
    JOIN main.int_comstock_models AS c
      ON c.comstock_id = m.comstock_id AND c.upgrade_id = 0
    JOIN main.stg_berdo__buildings AS b
      ON b.berdo_id = m.berdo_id
    WHERE b.property_type = 'Office'
),
neighbor_fuels AS (
    SELECT
        n.berdo_id, n.comstock_id, n.match_weight,
        f.fuel, f.baseline_kwh
    FROM baseline_neighbors AS n
    CROSS JOIN LATERAL (
        VALUES
          ('electricity', n.electricity_kwh),
          ('natural_gas', n.natural_gas_kwh),
          ('oil_propane', n.oil_propane_kwh),
          ('district_heating', n.district_heating_kwh),
          ('district_cooling', n.district_cooling_kwh)
    ) AS f(fuel, baseline_kwh)
),
coverage AS (
    SELECT
        berdo_id, fuel,
        COUNT(*) AS neighbor_count,
        COUNT(*) FILTER (WHERE baseline_kwh > 0) AS fuel_using_neighbors,
        COUNT(*) FILTER (WHERE baseline_kwh IS NULL) AS null_baseline_neighbors,
        SUM(match_weight) AS total_match_weight,
        SUM(match_weight) FILTER (WHERE baseline_kwh > 0) AS fuel_using_match_weight,
        SUM(match_weight * baseline_kwh) AS pooled_baseline_kwh
    FROM neighbor_fuels
    GROUP BY berdo_id, fuel
),
berdo_fuels AS (
    SELECT
        b.berdo_id, b.building_address, b.ghg_kgco2e AS building_ghg_kgco2e,
        f.fuel, f.berdo_kwh, f.fuel_ghg_kgco2e
    FROM main.stg_berdo__buildings AS b
    CROSS JOIN LATERAL (
        VALUES
          ('electricity', b.electricity_kwh, b.electricity_ghg_kgco2e),
          ('natural_gas', b.natural_gas_kwh, b.natural_gas_ghg_kgco2e),
          ('oil_propane', b.oil_propane_kwh, b.oil_propane_ghg_kgco2e),
          ('district_heating', b.district_heating_kwh, b.district_heating_ghg_kgco2e),
          ('district_cooling', b.district_cooling_kwh, b.district_cooling_ghg_kgco2e)
    ) AS f(fuel, berdo_kwh, fuel_ghg_kgco2e)
    WHERE b.property_type = 'Office' AND f.berdo_kwh > 0
)
SELECT
    b.berdo_id,
    b.building_address,
    b.fuel,
    c.neighbor_count,
    c.fuel_using_neighbors,
    c.null_baseline_neighbors,
    ROUND(100.0 * COALESCE(c.fuel_using_match_weight, 0)
          / NULLIF(c.total_match_weight, 0), 2) AS weighted_coverage_pct,
    ROUND(100.0 * b.fuel_ghg_kgco2e
          / NULLIF(b.building_ghg_kgco2e, 0), 2) AS fuel_emissions_share_pct,
    b.berdo_kwh,
    c.pooled_baseline_kwh,
    (c.pooled_baseline_kwh = 0) AS zero_matched_baseline
FROM berdo_fuels AS b
JOIN coverage AS c USING (berdo_id, fuel)
ORDER BY b.fuel, weighted_coverage_pct, b.berdo_id;
