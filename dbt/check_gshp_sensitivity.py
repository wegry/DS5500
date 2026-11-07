from pathlib import Path
import duckdb

db = Path(__file__).resolve().parent / "ds5500.duckdb"
con = duckdb.connect(str(db), read_only=True)

result = con.execute("""
WITH ground_loop AS (
    SELECT berdo_id,
        sum(installed_cost_low_usd - installed_cost_mid_usd) AS low_delta,
        sum(installed_cost_high_usd - installed_cost_mid_usd) AS high_delta
    FROM int_berdo_package_costs
    WHERE upgrade_id = 29 AND btb_measure_id = -29
    GROUP BY berdo_id
),
other_options AS (
    SELECT berdo_id,
        min(total_cost_mid_usd) AS cheapest_other,
        min(total_cost_mid_usd) FILTER (
            WHERE meets_standard
        ) AS cheapest_other_compliant
    FROM berdo_decision_options
    WHERE upgrade_id <> 29
    GROUP BY berdo_id
),
comparison AS (
    SELECT v.meets_standard,
        v.total_cost_mid_usd + g.low_delta AS low_cost,
        v.total_cost_mid_usd AS mid_cost,
        v.total_cost_mid_usd + g.high_delta AS high_cost,
        o.cheapest_other,
        o.cheapest_other_compliant
    FROM berdo_decision_options v
    JOIN ground_loop g USING (berdo_id)
    JOIN other_options o USING (berdo_id)
    JOIN berdo_decision_options b
        ON b.berdo_id = v.berdo_id AND b.upgrade_id = 0
    WHERE v.upgrade_id = 29 AND NOT b.meets_standard
)
SELECT scenario,
    count(*) FILTER (
        WHERE meets_standard
          AND cost < coalesce(cheapest_other_compliant, 1e99)
    ) AS cheapest_compliant,
    count(*) FILTER (
        WHERE cost < cheapest_other
    ) AS cheapest_overall
FROM comparison
CROSS JOIN LATERAL (
    VALUES
        ('Low (-30%)', low_cost),
        ('Mid', mid_cost),
        ('High (+30%)', high_cost)
) AS s(scenario, cost)
GROUP BY scenario
ORDER BY scenario
""").df()

print(result.to_string(index=False))
