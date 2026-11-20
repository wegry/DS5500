"""Plot ComStock leave-one-out MAE vs neighbor count.

Run from dbt/: python -m uv run python plot_matching_validation.py
Reads analysis_outputs/weighted_matching_summary.csv and loo_k_summary.csv.
Writes analysis_outputs/weighted_matching_mae.png and .pdf.
"""
import csv
from pathlib import Path

import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'analysis_outputs'


def read_csv(path):
    if not path.exists():
        raise FileNotFoundError(f'Missing {path}. Run the validation scripts first.')
    with path.open(newline='', encoding='utf-8-sig') as fh:
        return list(csv.DictReader(fh))


def main():
    weighted = read_csv(OUT / 'weighted_matching_summary.csv')
    existing = read_csv(OUT / 'loo_k_summary.csv')
    curves = {}
    for method in ('unweighted', 'inverse_distance'):
        points = sorted((int(r['k']), float(r['mae_pp'])) for r in weighted if r['method'] == method)
        if not points:
            raise ValueError(f'No rows for {method}')
        curves[method] = points
    loo = {int(r['k']): float(r['mae_pp']) for r in existing if r['k'].isdigit()}
    # Existing LOO output is rounded to 2 decimals, so allow rounding tolerance.
    differences = [(k, abs(mae - loo[k])) for k, mae in curves['unweighted'] if k in loo]
    if differences and max(d for _, d in differences) > 0.011:
        raise ValueError(f'Unweighted curve does not reproduce LOO baseline: {differences}')

    fig, ax = plt.subplots(figsize=(9, 5.5))
    for method, label, marker in [
        ('unweighted', 'Unweighted', 'o'),
        ('inverse_distance', 'Inverse-distance weighted', 's'),
    ]:
        points = curves[method]
        ax.plot([p[0] for p in points], [p[1] for p in points],
                label=label, marker=marker, markersize=3.5, linewidth=1.8)
    ax.set(title='Retrofit prediction error vs. number of neighbors',
           xlabel='Number of nearest neighbors (k)',
           ylabel='Mean absolute error (percentage points)')
    ax.set_xticks(sorted(set(k for points in curves.values() for k, _ in points)))
    ax.grid(True, alpha=0.25)
    ax.legend()
    fig.text(0.5, 0.01,
             'ComStock leave-one-out validation; 618 held-out models, 13 upgrades. Lower is better.',
             ha='center', fontsize=9)
    fig.tight_layout(rect=(0, 0.045, 1, 1))
    for ext in ('png', 'pdf'):
        path = OUT / f'weighted_matching_mae.{ext}'
        fig.savefig(path, dpi=220, bbox_inches='tight')
        print(f'Saved {path}')
    plt.close(fig)


if __name__ == '__main__':
    main()
