-- The var("decision_period_start") retrofit decision for each matched BERDO building: the
-- upgrades in comstock_package_components plus no retrofit (upgrade 0), each costed
-- over the 5-year standards period as installed cost + Alternative Compliance Payments on
-- the emissions still over the limit + energy bills. Energy use, prices and the ACP rate
-- are held constant across the period; the electricity part of the emissions follows
-- BERDO's projected factor year by year (berdo_upgrade_compliance.period_acp_usd), while
-- meets_standard and the intensity are the period's first year, its highest-factor year.
-- Running costs are not discounted. Equipment outlives the period (BTB lifetimes, median
-- ~21 years), so var("five_year_capital") sets how much of each component's installed cost
-- the period bears (capital_charged_*): 'annualized' charges period_years equivalent annual
-- costs at var("discount_rate_financial") (installed x r / (1 - (1 + r)^-lifetime) a year);
-- 'straight_line' charges period_years / lifetime of it, i.e. credits straight-line
-- remaining value at the period's end as berdo_global_cost does at its horizon; 'full'
-- charges all of it. Each is capped at the installed cost. Options that keep the existing
-- heating and cooling equipment (replaces_hvac false) are charged its like-for-like
-- replacement (int_berdo_existing_hvac) the same way (existing_hvac_charged_*), since it
-- wears out too; heat pump, VRF and geothermal options replace it instead, so in effect they
-- pay only their extra cost over like-for-like. With 'full' there is no such charge: when
-- the existing equipment fails in the period is unknown. Totals vary the installed costs
-- (low/mid/high) at mid energy prices; energy_cost_{low,high}_usd_per_year give the price
-- range.
-- Energy bills price the building's BERDO fuel use, scaled by the upgrade's per-fuel ratios
-- (1 for no retrofit), at the fuel_prices seed's flat $/kWh, so they leave out demand
-- charges and tariff structure. Grain: BERDO building x option.
-- The SQL is in macros/retrofit_chain.sql, shared with its analysis_k_* twin.
{{ berdo_decision_options(
    compliance=ref('berdo_upgrade_compliance'),
    scenarios=ref('berdo_upgrade_scenarios'),
    package_costs=ref('int_berdo_package_costs'),
    existing_hvac=ref('int_berdo_existing_hvac')
) }}
