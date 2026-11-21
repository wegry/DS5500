-- berdo_upgrade_compliance at every neighbor count k (analysis_k_matches).
-- Grain: k x BERDO building x upgrade x 5-year standards period.
{{ berdo_upgrade_compliance(
    scenarios=ref('analysis_k_upgrade_scenarios'),
    matches=ref('analysis_k_matches'),
    by_k=true
) }}
