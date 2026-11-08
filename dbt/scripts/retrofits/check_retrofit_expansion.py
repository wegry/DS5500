from pathlib import Path
import duckdb
import polars as pl

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "analysis_outputs" / "retrofits"
OUT.mkdir(exist_ok=True)

con = duckdb.connect(str(ROOT / "ds5500.duckdb"), read_only=True)

options = con.sql("""
    SELECT berdo_id, upgrade_id, upgrade_name, meets_standard,
           total_cost_mid_usd AS cost,
           projected_ghg_intensity_kgco2e_sqft AS ghg
    FROM berdo_decision_options
    WHERE berdo_id IN (
        SELECT berdo_id
        FROM berdo_decision_options
        WHERE upgrade_id = 0 AND NOT meets_standard
    )
""").pl()

cohort_size = options["berdo_id"].n_unique()

STAGES = [
    ("Original 8", [43, 48, 49, 52, 54, 55, 56, 57]),
    ("+ VRF", [12]),
    ("+ Geothermal", [29]),
    ("+ Package 5", [58]),
    ("+ Solar PV", [46, 65]),
]


def first_per_building(ranked):
    """{berdo_id: upgrade_id} for the first-ranked row of each building."""
    return dict(
        ranked.unique("berdo_id", keep="first", maintain_order=True)
        .select("berdo_id", "upgrade_id")
        .iter_rows()
    )


def choose(data):
    ranked = data.sort(
        ["berdo_id", "cost", "ghg", "upgrade_id"], nulls_last=True
    )
    overall = first_per_building(ranked)
    compliant = first_per_building(ranked.filter(pl.col("meets_standard")))
    return overall, compliant


def difference(old, new):
    return sum(
        old.get(bid, -1) != new.get(bid, -1)
        for bid in old.keys() | new.keys()
    )


included = {0}
previous = None
summary = []
changes = []

for name, added in STAGES:
    included.update(added)
    data = options.filter(pl.col("upgrade_id").is_in(included))
    overall, compliant = choose(data)

    newly = 0
    changed_overall = 0
    changed_compliant = 0

    if previous is not None:
        old_overall, old_compliant = previous
        newly = len(compliant.keys() - old_compliant.keys())
        changed_overall = difference(old_overall, overall)
        changed_compliant = difference(old_compliant, compliant)

        for bid in overall:
            old_o = old_overall.get(bid, -1)
            new_o = overall.get(bid, -1)
            old_c = old_compliant.get(bid, -1)
            new_c = compliant.get(bid, -1)

            if old_o != new_o or old_c != new_c:
                changes.append({
                    "stage": name,
                    "berdo_id": bid,
                    "previous_overall": old_o,
                    "new_overall": new_o,
                    "previous_compliant": old_c,
                    "new_compliant": new_c,
                })

    summary.append({
        "stage": name,
        "options": len(included) - 1,
        "buildings": len(overall),
        "compliant_coverage": len(compliant),
        "newly_covered": newly,
        "changed_overall": changed_overall,
        "changed_compliant": changed_compliant,
        "no_upgrade_cheapest": sum(u == 0 for u in overall.values()),
    })

    previous = overall, compliant

table = pl.Config(
    tbl_rows=-1,
    tbl_cols=-1,
    tbl_width_chars=200,
    tbl_hide_dataframe_shape=True,
    tbl_hide_column_data_types=True,
)

result = pl.DataFrame(summary)
print("\nRETROFIT EXPANSION")
with table:
    print(result)

result.write_csv(OUT / "retrofit_expansion_summary.csv")
pl.DataFrame(
    changes,
    schema=[
        "stage", "berdo_id",
        "previous_overall", "new_overall",
        "previous_compliant", "new_compliant",
    ],
).write_csv(OUT / "retrofit_expansion_changes.csv")


# Compare the original eight retrofits with all expanded options
# using the 20-year discounted global-cost model.
twenty_year = con.sql("""
WITH cohort AS (
    SELECT berdo_id
    FROM berdo_decision_options
    WHERE upgrade_id = 0 AND NOT meets_standard
),
old_best AS (
    SELECT berdo_id, perspective,
           upgrade_id AS old_upgrade,
           global_cost_mid_usd AS old_cost
    FROM berdo_global_cost
    WHERE energy_price = 'mid'
      AND upgrade_id IN (0, 43, 48, 49, 52, 54, 55, 56, 57)
      AND berdo_id IN (SELECT berdo_id FROM cohort)
    QUALIFY row_number() OVER (
        PARTITION BY berdo_id, perspective
        ORDER BY global_cost_mid_usd, upgrade_id
    ) = 1
),
new_best AS (
    SELECT berdo_id, perspective,
           upgrade_id AS new_upgrade,
           global_cost_mid_usd AS new_cost,
           meets_standard_at_start
    FROM berdo_global_cost
    WHERE energy_price = 'mid'
      AND berdo_id IN (SELECT berdo_id FROM cohort)
    QUALIFY row_number() OVER (
        PARTITION BY berdo_id, perspective
        ORDER BY global_cost_mid_usd, upgrade_id
    ) = 1
)
SELECT
    n.perspective,
    count(*) AS buildings,
    count(*) FILTER (
        WHERE o.old_upgrade <> n.new_upgrade
    ) AS changed_recommendations,
    count(*) FILTER (
        WHERE n.new_upgrade IN (12, 29, 46, 58, 65)
    ) AS new_upgrades_selected,
    count(*) FILTER (
        WHERE n.meets_standard_at_start
    ) AS selected_meet_standard,
    round(sum(o.old_cost - n.new_cost))
        AS modeled_savings_usd,
    count(*) FILTER (
        WHERE n.new_cost > o.old_cost + 0.01
    ) AS unexpected_cost_increases
FROM old_best o
JOIN new_best n USING (berdo_id, perspective)
GROUP BY n.perspective
ORDER BY n.perspective
""").pl()

print("\n20-YEAR OPTIMIZER COMPARISON")
with table:
    print(twenty_year)

assert (twenty_year["buildings"] == cohort_size).all()
assert (twenty_year["unexpected_cost_increases"] == 0).all()

twenty_year.write_csv(OUT / "retrofit_expansion_20yr.csv")

con.close()
