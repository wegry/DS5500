-- Installed cost of each package component for each matched BERDO building. Like the
-- emissions ratios, costs are pooled over the building's matched ComStock models (total
-- cost / total floor area, so a model the measure skips adds floor area at no cost) and
-- scaled to the building's BERDO floor area. Grain: BERDO building x package x component.
-- The SQL is in macros/retrofit_chain.sql, shared with its analysis_k_* twin.
{{ berdo_package_costs(matches=ref('int_berdo_comstock_matches')) }}
