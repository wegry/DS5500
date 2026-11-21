# Full K-Sensitivity Validation

Evaluates the five-year BERDO optimizer for K=1 through the project's `match_k` (20) ComStock neighbors across the 81 Boston offices over the 2030 limit as BERDO will count emissions in 2030 (its projected grid factor; 99 at today's factor).

The analysis_k_* dbt models rerun the whole retrofit chain at every K in one build: matching, retrofit installation costs, projected emissions, energy costs, ACPs, and optimal recommendations. They share the production models' SQL (dbt/macros/retrofit_chain.sql), and a dbt test checks that K = `match_k` reproduces `berdo_decisions`.

## Reproduce

From the dbt directory, `uv run dbt build` writes data/full_k_decisions.csv, full_k_options.csv, full_k_summary.csv and full_k_changes.csv.

full_k_report.txt, figures/, full_k_building_stability.csv and full_k_change_diagnostics.csv come from `summarize_full_k_sensitivity.py`. It still compares against a K=10 reference, so these files predate the move to K=20.

## Outputs

- data/: the CSVs above
- full_k_report.txt and figures/: the older K=10 summary

K=`match_k` is the reference, not ground truth. This measures model sensitivity, not predictive accuracy.
