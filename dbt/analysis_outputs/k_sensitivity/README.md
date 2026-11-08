# Full K-Sensitivity Validation

Evaluates the five-year BERDO optimizer for K=1 through K=10 ComStock neighbors across the 81 Boston offices over the 2030 limit as BERDO will count emissions in 2030 (its projected grid factor; 99 at today's factor).

Unlike the earlier sensitivity analysis, this experiment rebuilds the matching, retrofit installation costs, projected emissions, energy costs, ACPs, and optimal recommendations at each K.

## Reproduce

From the dbt directory:

1. uv run python check_full_k_sensitivity.py
2. uv run python summarize_full_k_sensitivity.py

Run using the project's Python environment.

## Outputs

- full_k_report.txt: summary of findings
- data/: six reproducible CSVs
- figures/: recommendation changes and optimizer outcomes

K=10 is the reference, not ground truth. This measures model sensitivity, not predictive accuracy.
