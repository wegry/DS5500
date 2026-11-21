-- BERDO compliance by period for each matched building under each ComStock upgrade, plus
-- upgrade 0 (no retrofit). Grain: building x upgrade x 5-year standards period.
-- Energy use is held at the disclosed year's level. The electricity part of the emissions
-- follows BERDO's projected electricity factor (int_berdo_electricity_index): compliance,
-- intensity and acp_usd_per_year use the period's first year, as in berdo_global_cost's
-- check in its first year, while period_acp_usd sums each year's payment at that year's
-- factor (null for the open-ended 2050+ period).
-- The SQL is in macros/retrofit_chain.sql, shared with its analysis_k_* twin.
{{ berdo_upgrade_compliance(
    scenarios=ref('berdo_upgrade_scenarios'),
    matches=ref('int_berdo_comstock_matches')
) }}
