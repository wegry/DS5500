-- int_berdo_existing_hvac at every neighbor count k (analysis_k_matches).
-- Grain: k x BERDO building x existing component.
{{ berdo_existing_hvac(matches=ref('analysis_k_matches'), by_k=true) }}
