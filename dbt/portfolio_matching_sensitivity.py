"""Read-only matching sensitivity on the current dbt leave-one-out cohort.

Run from the repository root with the project's Python environment:
    uv run python dbt/portfolio_matching_sensitivity.py

Use --with-hvac to read the configured public ComStock full baseline Parquet,
or --hvac-source to use a local copy. The older HVAC procedure is unavailable.
Outputs go to analysis_outputs/portfolio_matching_sensitivity. No production
tables, exports, or parameters are written.
"""
import argparse
import csv
from pathlib import Path

import duckdb
import numpy as np
import yaml

from weighted_matching_validation import EPS, FUELS, write_csv

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "analysis_outputs" / "portfolio_matching_sensitivity"
FIELDS = ("mae_pp", "median_ae_pp", "p90_ae_pp")


def cohort(con):
    pairs = con.sql("""
        select held_out_id, neighbor_id, district_agrees, size_gap, eui_gap,
               fuel_share_gap, stories_gap, distance
        from analysis_loo_neighbors order by held_out_id, neighbor_id
    """).fetchnumpy()
    ids, lengths = np.unique(pairs["held_out_id"], return_counts=True)
    if not np.all(lengths == len(ids) - 1):
        raise ValueError("Incomplete leave-one-out candidate pairs")
    shape = (len(ids), len(ids) - 1)
    neighbors = np.searchsorted(ids, pairs["neighbor_id"]).reshape(shape)
    if not np.array_equal(ids[neighbors].ravel(), pairs["neighbor_id"]):
        raise ValueError("Candidate and held-out cohorts differ")
    eligible = pairs["district_agrees"].reshape(shape)
    gaps = np.stack([pairs[x].reshape(shape) for x in (
        "size_gap", "eui_gap", "fuel_share_gap", "stories_gap",
    )])
    distance = pairs["distance"].reshape(shape)
    return ids, neighbors, eligible, gaps, distance


def fuel_use(con, ids):
    fuels = ", ".join(f"{f}_kwh" for f in FUELS)
    rows = con.execute(f"""
        select comstock_id, upgrade_id, {fuels}
        from int_comstock_models
        where comstock_id in (select unnest(?))
          and upgrade_id in (select distinct upgrade_id from berdo_decision_options)
        order by comstock_id, upgrade_id
    """, [ids.tolist()]).fetchnumpy()
    upgrades = np.unique(rows["upgrade_id"])
    if upgrades[0] != 0 or not (
        np.array_equal(rows["comstock_id"], np.repeat(ids, len(upgrades)))
        and np.array_equal(rows["upgrade_id"], np.tile(upgrades, len(ids)))
    ):
        raise ValueError("Incomplete or duplicate fuel-use rows for the portfolio")
    use = np.stack([rows[f"{f}_kwh"] for f in FUELS], axis=-1)
    use = use.reshape(len(ids), len(upgrades), len(FUELS))
    factors = con.sql("select " + ", ".join(
        f"median({f}_ghg_kgco2e / {f}_kwh) filter (where {f}_kwh > 0)" for f in FUELS
    ) + " from int_berdo_match_buildings").fetchall()[0]
    factors = np.array([x if x is not None else (
        factors[0] / 4 if f == "district_cooling" else np.nan
    ) for f, x in zip(FUELS, factors)])
    if not np.isfinite(factors).all():
        raise ValueError("Missing emissions factors")
    return upgrades[1:], use[:, 0], use[:, 1:], factors


def standardized_weights(con):
    # Extend metric_sensitivity.py's BERDO-pair SD scaling to four terms.
    gaps = con.sql("""
        with m as (select *, electricity_kwh + natural_gas_kwh + oil_propane_kwh
                          + district_heating_kwh + district_cooling_kwh as total
                   from int_comstock_models where upgrade_id=0)
        select stddev(abs(ln(b.gfa_sqft/m.gfa_sqft))),
               stddev(abs(ln(b.eui_kwh_sqft/m.eui_kwh_sqft))),
               stddev(0.5 * (
                   abs(b.electricity_share-m.electricity_kwh/m.total)
                 + abs(b.natural_gas_share-m.natural_gas_kwh/m.total)
                 + abs(b.oil_propane_share-m.oil_propane_kwh/m.total)
                 + abs(b.district_share-(m.district_heating_kwh+m.district_cooling_kwh)/m.total))),
               stddev(coalesce(abs(ln(b.stories/m.stories)),0))
        from int_berdo_match_buildings b
        join berdo_comstock_type_crosswalk w on w.berdo_type=b.property_type
        join m on m.comstock_type=w.comstock_type
        where m.gfa_sqft>0 and m.eui_kwh_sqft>0 and m.total>0
    """).fetchall()[0]
    inv = 1 / np.array(gaps)
    return np.round(len(gaps) * inv / inv.sum(), 3)


def metrics(err):
    return np.array([err.mean(), np.median(err), np.quantile(err, 0.9)])


def hvac_labels(con, path, ids):
    rows = con.execute("""
        select distinct bldg_id, "in.hvac_system_type"
        from read_parquet(?) where bldg_id in (select unnest(?))
        order by bldg_id
    """, [path, ids.tolist()]).fetchall()
    if [r[0] for r in rows] != ids.tolist() or any(not r[1] for r in rows):
        raise ValueError("HVAC metadata must cover every held-out model exactly once")
    return np.array([r[1] for r in rows])


def cost_audit(con, config, upgrades):
    # Independently re-rank the materialized 20-year costs, preserving
    # building-level applicability and the production tie-break rule.
    k_ref = config["match_k"]
    rows = con.execute("""
        with costs as (
            select * from analysis_k_global_cost
            where scenario = 'projected' and energy_price = 'mid'
        ), cohort as (
            select distinct berdo_id from costs
            where upgrade_id = 0 and not meets_standard_at_start
        ), ranked as (
            select *, row_number() over (
                partition by k, perspective, berdo_id
                order by round(global_cost_mid_usd, 2), upgrade_id
            ) as cost_rank
            from costs join cohort using (berdo_id)
        ), picks as (
            select k, perspective, berdo_id, count(*) as available_options,
                first(upgrade_id order by cost_rank) as overall,
                first(meets_standard_at_start order by cost_rank) as overall_meets,
                first(upgrade_id order by cost_rank)
                    filter (where meets_standard_at_start) as compliant
            from ranked group by all
        ), availability as (
            select k, perspective, any_value(discount_rate) as discount_rate,
                list(distinct upgrade_id order by upgrade_id) as portfolio
            from costs group by all
        )
        select p.perspective, p.k, a.discount_rate, any_value(a.portfolio) as portfolio,
            count(*) as offices, count(p.compliant) as has_compliant_option,
            count(*) filter (where p.overall <> 0) as retrofit_cheapest,
            count(*) filter (where p.overall_meets) as cheapest_meets_standard,
            count(*) filter (where p.overall <> r.overall) as cheapest_changed_vs_ref,
            count(*) filter (where p.compliant is not null and r.compliant is not null)
                as compliant_compared,
            count(*) filter (where p.compliant <> r.compliant)
                as cheapest_compliant_changed_vs_ref,
            min(p.available_options) as min_options_including_baseline,
            max(p.available_options) as max_options_including_baseline
        from picks p
        join picks r on p.perspective = r.perspective and p.berdo_id = r.berdo_id
            and r.k = ?
        join availability a on p.k = a.k and p.perspective = a.perspective
        group by p.perspective, p.k, a.discount_rate order by 1, 2
    """, [k_ref])
    columns = [x[0] for x in rows.description]
    data = rows.fetchall()
    with (ROOT / "analysis_outputs/k_sensitivity/data/global_k_summary.csv").open(newline="") as f:
        expected = {(r["perspective"], int(r["k"])): r for r in csv.DictReader(f)}
    rates = {p: config[f"discount_rate_{p}"] for p in ("financial", "societal")}
    if set(expected) != {(r[0], r[1]) for r in data}:
        raise ValueError("Cost sensitivity configurations differ from the reference export")
    output = []
    for perspective, k, rate, portfolio, *counts in data:
        if portfolio != [0, *upgrades.tolist()] or float(rate) != rates[perspective]:
            raise ValueError(f"Cost portfolio or discount rate drift at {k=}, {perspective=}")
        for col, value in zip(columns[4:], counts):
            if col in expected[perspective, k] and value != int(expected[perspective, k][col]):
                raise ValueError(f"Cost summary drift at {k=}, {perspective=}, {col=}")
        output.append((perspective, k, rate, len(portfolio) - 1, *counts))
    write_csv(OUT / "global_cost_k_check.csv", (*columns[:3], "portfolio_upgrades", *columns[4:]), output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hvac-source", help="Full baseline Parquet path or URL")
    parser.add_argument("--with-hvac", action="store_true", help="Read the configured public ComStock baseline")
    parser.add_argument("--seed", type=int, default=5500)
    parser.add_argument("--replicates", type=int, default=20)
    args = parser.parse_args()
    if args.replicates < 1:
        parser.error("--replicates must be positive")
    config = yaml.safe_load((ROOT / "dbt_project.yml").read_text())["vars"]
    k_ref = config["match_k"]
    production_weight = config["match_weighting"]
    production_rule = config["match_district_rule"]
    with duckdb.connect(str(ROOT / "ds5500.duckdb"), read_only=True) as con:
        ids, neighbors, eligible, gaps, distance = cohort(con)
        upgrades, baseline, upgraded, factors = fuel_use(con, ids)
        scaling = standardized_weights(con)
        source = args.hvac_source
        if args.with_hvac and not source:
            con.execute("load httpfs")
            source = f"{config['comstock_full_dir']}/{config['comstock_county_prefix']}_upgrade0.parquet"
        labels = hvac_labels(con, source, ids) if source else None
        cost_audit(con, config, upgrades)
    base_ghg = baseline @ factors
    if not np.all(base_ghg > 0):
        raise ValueError("Nonpositive held-out baseline emissions")
    actual = upgraded @ factors
    actual_reduction = 100 * (1 - actual / base_ghg[:, None])

    def ranking(d, rule):
        # Candidate IDs already ascending, so a stable sort resolves ties by ID.
        return np.argsort(np.where(eligible, d, np.inf) if rule else d, axis=1, kind="stable")

    def predict(d, ordering, k, method, rule):
        ix = ordering[:, :k]
        if rule and not np.take_along_axis(eligible, ix, axis=1).all():
            raise ValueError("Too few district-compatible neighbors")
        ns = np.take_along_axis(neighbors, ix, axis=1)
        w = 1 / (np.take_along_axis(d, ix, axis=1) + EPS) if method == "inverse_distance" else np.ones(ns.shape)
        pooled_base = np.einsum("nk,nkf->nf", w, baseline[ns])
        pooled_upgrade = np.einsum("nk,nkuf->nuf", w, upgraded[ns])
        ratio = np.divide(pooled_upgrade, pooled_base[:, None], out=np.ones_like(pooled_upgrade),
                          where=pooled_base[:, None] != 0)
        predicted = ratio @ (factors * baseline)[:, :, None]
        return 100 * np.abs(actual - predicted[:, :, 0]) / base_ghg[:, None]

    ref = predict(distance, ranking(distance, production_rule), k_ref, production_weight, production_rule)
    reference = metrics(ref)
    settings = (
        ("production", distance, (1, 1, 1, 1)),
        ("without_stories", distance - gaps[3], (1, 1, 1, 0)),
        ("four_term_sd_scaled", np.einsum("t,tnm->nm", scaling, gaps), scaling),
        ("fuel_half", distance - 0.5 * gaps[2], (1, 1, 0.5, 1)),
        ("fuel_triple", distance + 2 * gaps[2], (1, 1, 3, 1)),
    )
    summary = []
    header = (
        "experiment", "k", "weighting", "district_rule", "size_weight", "eui_weight",
        "fuel_term_weight", "stories_weight", "held_out_models", "upgrades",
        "predictions", *FIELDS, "mae_minus_production_pp",
    )

    def add(name, k, method, rule, coefficients, errors):
        scores = metrics(errors)
        summary.append((name, k, method, str(rule).lower(), *coefficients, len(ids),
                        len(upgrades), errors.size, *scores.round(6),
                        round(scores[0] - reference[0], 6)))

    with (ROOT.parent / "report-2/data/matching_validation.csv").open(newline="", encoding="utf-8") as f:
        archived = list(csv.DictReader(f))
    for rule in (False, True):
        ordered = ranking(distance, rule)
        for method in ("unweighted", "inverse_distance"):
            for row in (x for x in archived if x["method"] == method and x["rule"] == str(rule).lower()):
                k = int(row["k"])
                errors = predict(distance, ordered, k, method, rule)
                if errors.size != int(row["predictions"]) or not np.allclose(
                    metrics(errors), [float(row[f]) for f in FIELDS], atol=0.000500001, rtol=0,
                ):
                    raise ValueError(f"Production validation drift at {k=}, {method=}, {rule=}")
                add("neighbor_sweep", k, method, rule, (1, 1, 1, 1), errors)

    for name, d, coefficients in settings:
        add(name, k_ref, production_weight, production_rule, coefficients,
            predict(d, ranking(d, production_rule), k_ref, production_weight, production_rule))

    write_csv(OUT / "configuration_summary.csv", header, summary)
    write_csv(OUT / "production_by_upgrade.csv",
              ("upgrade_id", "predictions", "mean_simulated_reduction_pct", *FIELDS),
              [(uid, len(ids), round(actual_reduction[:, i].mean(), 6), *metrics(ref[:, i]).round(6))
               for i, uid in enumerate(upgrades)])

    if labels is not None:
        # New test, since the old HVAC distance and noise protocol were not archived.
        # Add one distance unit for a label mismatch. Corrupt held-out labels only,
        # selecting models without replacement and assigning a different class uniformly.
        rng = np.random.default_rng(args.seed)
        classes = np.unique(labels)
        replicates = []
        for rep in range(args.replicates):
            order = rng.permutation(len(ids))
            wrong = np.array([rng.choice(classes[classes != label]) for label in labels])
            for rate in (0, 0.10, 0.25, 0.33, 0.50):
                if rate == 0 and rep != 0:
                    continue
                n = round(rate * len(ids))
                observed = labels.copy()
                observed[order[:n]] = wrong[order[:n]]
                d = distance + (observed[:, None] != labels[neighbors])
                error = predict(d, ranking(d, production_rule), k_ref, production_weight, production_rule)
                scores = metrics(error)
                replicates.append((rate, rep, args.seed, n, len(ids), len(upgrades),
                                   error.size, *scores.round(6),
                                   round(scores[0] - reference[0], 6)))
        write_csv(OUT / "hvac_label_replicates.csv",
                  ("target_error_rate", "replicate", "seed", "mislabeled_models", "held_out_models",
                   "upgrades", "predictions", *FIELDS, "mae_minus_production_pp"), replicates)
    print(f"Production: {len(ids)} models x {len(upgrades)} upgrades, {reference.round(3)} pp")


if __name__ == "__main__":
    main()
