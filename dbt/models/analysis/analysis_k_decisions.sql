-- berdo_decisions at every neighbor count k (analysis_k_matches). At k = var("match_k") it
-- equals berdo_decisions (tests/analysis_k_reference_matches_production.sql).
-- Grain: k x BERDO building.
{{ berdo_decisions(options=ref('analysis_k_decision_options'), by_k=true) }}
