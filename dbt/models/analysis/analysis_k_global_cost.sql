-- berdo_global_cost at every neighbor count k (analysis_k_matches), for the projected energy
-- scenario at mid energy prices only, to keep the k x building x option grid small. At
-- k = var("match_k") it equals berdo_global_cost (tests/analysis_k_global_cost_matches_production.sql).
-- Grain: k x BERDO building x option x perspective.
{{ berdo_global_cost(
    options=ref('analysis_k_decision_options'),
    scenarios=ref('analysis_k_upgrade_scenarios'),
    package_costs=ref('analysis_k_package_costs'),
    existing_hvac=ref('analysis_k_existing_hvac'),
    by_k=true,
    scenario_names=['projected'],
    energy_prices=['mid']
) }}
