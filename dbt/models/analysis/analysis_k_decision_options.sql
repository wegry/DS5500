-- berdo_decision_options at every neighbor count k (analysis_k_matches).
-- Grain: k x BERDO building x option.
{{ berdo_decision_options(
    compliance=ref('analysis_k_upgrade_compliance'),
    scenarios=ref('analysis_k_upgrade_scenarios'),
    package_costs=ref('analysis_k_package_costs'),
    existing_hvac=ref('analysis_k_existing_hvac'),
    by_k=true
) }}
