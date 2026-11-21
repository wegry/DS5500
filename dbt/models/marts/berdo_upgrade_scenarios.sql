-- BERDO x ComStock upgrades. Grain: one row per BERDO building x ComStock upgrade.
-- ComStock is synthetic, so each building borrows the modeled effect of each upgrade from
-- its nearest ComStock models: per fuel, upgrade use / baseline use pooled over the
-- matches. Those ratios are applied to the building's actual BERDO fuel use and per-fuel
-- emissions, so the projection keeps BERDO's own emission factors.
-- A fuel the matched models do not use keeps a ratio of 1 (unchanged); for a building on
-- district steam whose matches burn gas, electrification therefore adds electricity
-- without removing the steam, and the projection is pessimistic.
-- The SQL is in macros/retrofit_chain.sql, shared with its analysis_k_* twin.
{{ berdo_upgrade_scenarios(matches=ref('int_berdo_comstock_matches')) }}
