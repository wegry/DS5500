-- int_berdo_package_costs at every neighbor count k (analysis_k_matches).
-- Grain: k x BERDO building x package x component.
{{ berdo_package_costs(matches=ref('analysis_k_matches'), by_k=true) }}
