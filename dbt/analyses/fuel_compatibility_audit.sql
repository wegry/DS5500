-- Fuel compatibility audit, all matched office buildings.
-- Uses the same ComStock baseline relation and match weights as retrofit_chain.sql.
-- Run against the materialized dbt DuckDB database.
WITH matched_baselines AS (
    SELECT
        m.berdo_id,
        COUNT(*) AS neighbor_count,
        SUM(m.match_weight * c.electricity_kwh) AS electricity_matched_kwh,
        SUM(m.match_weight * c.natural_gas_kwh) AS natural_gas_matched_kwh,
        SUM(m.match_weight * c.oil_propane_kwh) AS oil_propane_matched_kwh,
        SUM(m.match_weight * c.district_heating_kwh) AS district_heating_matched_kwh,
        SUM(m.match_weight * c.district_cooling_kwh) AS district_cooling_matched_kwh
    FROM main.int_berdo_comstock_matches AS m
    JOIN main.int_comstock_models AS c
      ON m.comstock_id = c.comstock_id AND c.upgrade_id = 0
    GROUP BY m.berdo_id
),
buildings AS (
    SELECT
        b.berdo_id,
        b.building_address,
        b.property_type,
        b.ghg_kgco2e AS baseline_ghg_kgco2e,
        mb.neighbor_count,
        b.electricity_kwh, b.electricity_ghg_kgco2e,
        b.natural_gas_kwh, b.natural_gas_ghg_kgco2e,
        b.oil_propane_kwh, b.oil_propane_ghg_kgco2e,
        b.district_heating_kwh, b.district_heating_ghg_kgco2e,
        b.district_cooling_kwh, b.district_cooling_ghg_kgco2e,
        mb.electricity_matched_kwh, mb.natural_gas_matched_kwh,
        mb.oil_propane_matched_kwh, mb.district_heating_matched_kwh,
        mb.district_cooling_matched_kwh
    FROM main.stg_berdo__buildings AS b
    JOIN matched_baselines AS mb USING (berdo_id)
    WHERE b.property_type = 'Office'
),
by_fuel AS (
    SELECT
        berdo_id, building_address, neighbor_count, baseline_ghg_kgco2e,
        f.fuel, f.berdo_kwh, f.berdo_ghg_kgco2e, f.matched_kwh,
        (f.berdo_kwh > 0) AS uses_fuel,
        (f.berdo_kwh > 0 AND f.matched_kwh = 0) AS zero_matched_baseline,
        100.0 * f.berdo_ghg_kgco2e / NULLIF(baseline_ghg_kgco2e, 0) AS emissions_share_pct
    FROM buildings
    CROSS JOIN LATERAL (
        VALUES
            ('electricity', electricity_kwh, electricity_ghg_kgco2e, electricity_matched_kwh),
            ('natural_gas', natural_gas_kwh, natural_gas_ghg_kgco2e, natural_gas_matched_kwh),
            ('oil_propane', oil_propane_kwh, oil_propane_ghg_kgco2e, oil_propane_matched_kwh),
            ('district_heating', district_heating_kwh, district_heating_ghg_kgco2e, district_heating_matched_kwh),
            ('district_cooling', district_cooling_kwh, district_cooling_ghg_kgco2e, district_cooling_matched_kwh)
    ) AS f(fuel, berdo_kwh, berdo_ghg_kgco2e, matched_kwh)
)
SELECT
    fuel,
    COUNT(*) AS matched_offices,
    COUNT(*) FILTER (WHERE uses_fuel) AS offices_using_fuel,
    COUNT(*) FILTER (WHERE zero_matched_baseline) AS unsupported_offices,
    ROUND(100.0 * COUNT(*) FILTER (WHERE zero_matched_baseline)
        / NULLIF(COUNT(*) FILTER (WHERE uses_fuel), 0), 2) AS unsupported_pct_of_users,
    ROUND(MAX(emissions_share_pct) FILTER (WHERE zero_matched_baseline), 2) AS max_flagged_emissions_share_pct,
    ROUND(AVG(emissions_share_pct) FILTER (WHERE zero_matched_baseline), 2) AS avg_flagged_emissions_share_pct,
    ROUND(SUM(berdo_ghg_kgco2e) FILTER (WHERE zero_matched_baseline), 2) AS unsupported_ghg_kgco2e
FROM by_fuel
GROUP BY fuel
ORDER BY fuel;
