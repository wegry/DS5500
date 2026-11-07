from pathlib import Path
import duckdb

con = duckdb.connect(
    str(Path(__file__).resolve().parent / "ds5500.duckdb"),
    read_only=True
)

# Vary only the imputed components.
# Keep all BTB-based costs at their mid estimates.
upgrades = {
    29: ("Geothermal ground loop", "-29"),
    58: (
    "Package 5 full installation",
    "2, 3, 5, 7, 12, -58, -59"),
}

for upgrade_id, (label, component_ids) in upgrades.items():

    df = con.execute(f"""
        WITH deltas AS (
            SELECT
                berdo_id,
                sum(installed_cost_low_usd
                    - installed_cost_mid_usd) AS low_delta,
                sum(installed_cost_high_usd
                    - installed_cost_mid_usd) AS high_delta
            FROM int_berdo_package_costs
            WHERE upgrade_id = ?
              AND btb_measure_id IN ({component_ids})
            GROUP BY berdo_id
        ),
        alternatives AS (
            SELECT
                berdo_id,
                min(total_cost_mid_usd) AS cheapest_other,
                min(total_cost_mid_usd) FILTER (
                    WHERE meets_standard
                ) AS cheapest_other_compliant
            FROM berdo_decision_options
            WHERE upgrade_id <> ?
            GROUP BY berdo_id
        ),
        comparison AS (
            SELECT
                p.meets_standard,
                p.total_cost_mid_usd AS mid_cost,
                p.total_cost_mid_usd + d.low_delta AS low_cost,
                p.total_cost_mid_usd + d.high_delta AS high_cost,
                a.cheapest_other,
                a.cheapest_other_compliant
            FROM berdo_decision_options p
            JOIN deltas d USING (berdo_id)
            JOIN alternatives a USING (berdo_id)
            JOIN berdo_decision_options b
                ON p.berdo_id = b.berdo_id
               AND b.upgrade_id = 0
            WHERE p.upgrade_id = ?
              AND NOT b.meets_standard
        )
        SELECT
            scenario,
            count(*) FILTER (
                WHERE meets_standard
                  AND cost < coalesce(
                      cheapest_other_compliant, 1e99
                  ) - 0.01
            ) AS cheapest_compliant,
            count(*) FILTER (
                WHERE cost < cheapest_other - 0.01
            ) AS cheapest_overall
        FROM comparison
        CROSS JOIN LATERAL (
            VALUES
                (1, 'Low', low_cost),
                (2, 'Mid', mid_cost),
                (3, 'High', high_cost)
        ) AS s(ord, scenario, cost)
        GROUP BY ord, scenario
        ORDER BY ord
    """, [upgrade_id, upgrade_id, upgrade_id]).df()

    print(f"\n{label} (upgrade {upgrade_id})")
    print(df.to_string(index=False))

con.close()
