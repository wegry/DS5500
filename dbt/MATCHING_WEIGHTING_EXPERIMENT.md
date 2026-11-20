# Inverse-distance weighting for ComStock retrofit transfer

## Objective

Test whether giving more influence to nearby ComStock analogs improves retrofit emissions predictions compared with the existing equal-weight, k-nearest-neighbor transfer. This is an **offline validation experiment**, not a change to the BERDO production decision models.

## Method

The experiment uses leave-one-out (LOO) validation on eligible ComStock baseline models. For each held-out model, the script finds the nearest other ComStock models using the existing matching-distance structure:

- Absolute log gross-floor-area ratio
- Absolute log energy-use-intensity ratio
- Half the sum of absolute fuel-share differences (electricity, natural gas, oil/propane, and combined district energy)

The script tests neighborhood sizes **k = 1 through 24** and two methods:

- **Unweighted:** all selected neighbors have weight 1.
- **Inverse-distance:** neighbor weight is `1 / (distance + 1e-6)`.

For each retrofit package and fuel, the script computes a pooled upgraded-to-baseline energy ratio:

`ratio_fuel = sum(weight * neighbor_upgraded_fuel_kwh) / sum(weight * neighbor_baseline_fuel_kwh)`

It applies these ratios to the held-out model's baseline fuel consumption and calculates predicted and actual retrofit emissions using the same fuel-specific emissions factors. Where the denominator for a fuel is zero, the ratio defaults to 1. The error is the absolute difference between predicted and actual emissions, expressed as a **percentage of the held-out model's baseline emissions** (percentage points, pp). Thus the reported MAE is *not* percentage error relative to actual upgraded emissions.

The evaluation contains **618 held-out models**, **13 upgrade packages**, and **8,034 model-upgrade predictions per configuration**.

## Results

| k | Unweighted MAE (pp) | Inverse-distance MAE (pp) | Weighted minus unweighted (pp) | Paired bootstrap 95% CI (pp) |
|---:|---:|---:|---:|---:|
| 10 | 7.225 | 7.149 | -0.0762 | [-0.1894, 0.0329] |
| 15 | 7.157 | 7.071 | -0.0868 | [-0.1975, 0.0276] |
| 20 | 7.195 | 7.072 | -0.1228 | [-0.2364, -0.0130] |

For k=1, the two methods are identical by construction (MAE 8.501 pp). At k=2–4, weighting performs slightly worse. At larger k, weighting generally has lower MAE. The lowest displayed weighted MAE is approximately **7.070 pp at k=21**, although differences around the minimum are small and should not be interpreted as identifying a uniquely optimal k.

### Uncertainty assessment

The script uses **4,000 paired bootstrap resamples** with a fixed random seed. The sampling unit is the **held-out ComStock model**, preserving its 13 upgrade outcomes as one cluster. The reported difference is `MAE_weighted - MAE_unweighted`, so negative values favor weighting. Percentile 95% intervals at k=10 and k=15 include zero; the interval at k=20 excludes zero.

These intervals describe resampling uncertainty **within this simulated ComStock validation sample**. The neighborhood sizes were examined as part of an exploratory sweep, so the k=20 result should not be treated as a preregistered confirmatory test. No direct BERDO ground-truth retrofit outcomes were available for this evaluation.

## Interpretation and recommendation

Inverse-distance weighting is a plausible improvement for larger neighborhoods, but its absolute MAE reduction is modest. At the current **k=10** setting, the observed reduction is **0.076 pp**, and the paired interval includes zero. **Do not replace the production matching logic solely on this experiment.** Consider additional validation of retrofit rankings, building-level error heterogeneity, and whether any change affects BERDO compliance or cost recommendations.

## Reproduction

From the repository's `dbt/` directory, with the dbt-built `ds5500.duckdb` available:

```powershell
python -m uv run python weighted_matching_validation.py
python -m uv run python plot_matching_validation.py
```

Outputs under `dbt/analysis_outputs/`:

- `weighted_matching_summary.csv`: MAE, median absolute error, and 90th-percentile absolute error by method and k
- `weighted_matching_by_upgrade.csv`: MAE by upgrade, method, and k
- `weighted_matching_bootstrap.csv`: paired differences and confidence intervals for k=10, 15, and 20
- `weighted_matching_mae.png`: comparison across k=1–24

The validation script connects to DuckDB in **read-only** mode and creates temporary tables only. It does not modify dbt models or production outputs.

## Limitations

- Validation holds out simulated ComStock models, not real BERDO buildings with observed retrofit outcomes.
- The experiment compares two weighting rules using the same distance function; it does not independently validate that distance function or the suitability of candidate upgrades.
- Emissions factors are derived from available BERDO building data; results are conditional on those factors and the chosen energy-transfer formulation.
- The experiment measures emissions-prediction error, not downstream compliance decisions, retrofit costs, or decision robustness.
- Multiple k values were explored; apparent best-performing k values may be sample-specific.
