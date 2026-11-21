-- berdo_upgrade_scenarios at every neighbor count k (analysis_k_matches).
-- Grain: k x BERDO building x ComStock upgrade.
{{ berdo_upgrade_scenarios(matches=ref('analysis_k_matches'), by_k=true) }}
