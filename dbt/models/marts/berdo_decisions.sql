-- The minimum-cost var("decision_period_start") option for each matched BERDO building
-- (a retrofit package or no retrofit + ACPs, with energy bills), at BTB mid costs, with the choice under low
-- and high costs to show whether it depends on the cost estimate.
-- Grain: one row per matched BERDO building.
-- The SQL is in macros/retrofit_chain.sql, shared with its analysis_k_* twin.
{{ berdo_decisions(options=ref('berdo_decision_options')) }}
