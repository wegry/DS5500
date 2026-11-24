"""Regenerate every tracked analysis output after a model change.

    uv run python dbt/regenerate.py            # from the DS5500 root
    uv run python dbt/regenerate.py --no-report

1. `dbt build`: the models, their tests, and the analysis models that write their CSVs
   (leave-one-out validation, matching validation, k sensitivity, and Report 2's
   matching_validation.csv).
2. The 20-year Monte Carlo, which stays in Python for its sampling: a zero-uncertainty
   check against dbt, then the full run with the settings below.
3. The matching sensitivity (dbt/portfolio_matching_sensitivity.py --with-hvac): the
   feature, HVAC-label, and per-option leave-one-out tables, the decision-level agreement
   table, and the cross-validated distance coefficients in Report 2.
4. Report 2's figures (report-2/make_berdo_figures.py), whose annotations quote model
   results, then Report 2, compiled to check that it still builds (the PDF is not tracked).

Stops at the first failing step.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

DBT = Path(__file__).resolve().parent
ROOT = DBT.parent
BIN = Path(sys.executable).parent

# Monte Carlo settings of the tracked outputs (analysis_outputs/monte_carlo_20yr/)
DRAWS, SEED = 5000, 5500
# assumed triangular discount-rate bounds (not sourced probabilities)
OWNER_RATES, SOCIETAL_RATES = ("0.05", "0.09"), ("0.01", "0.03")


def run(label: str, command: list[str], cwd: Path = ROOT) -> None:
    print(f"\n== {label}", flush=True)
    if subprocess.run(command, cwd=cwd).returncode:
        sys.exit(f"Failed: {label}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--no-report", action="store_true", help="skip compiling Report 2")
    args = parser.parse_args()

    run("dbt build", [str(BIN / "dbt"), "build"], cwd=DBT)

    py = sys.executable
    run("20-year Monte Carlo check", [py, "dbt/monte_carlo_20year.py", "--zero-uncertainty"])
    run("20-year Monte Carlo",
        [py, "dbt/monte_carlo_20year.py", "--draws", str(DRAWS), "--seed", str(SEED),
         "--owner-rate-range", *OWNER_RATES, "--societal-rate-range", *SOCIETAL_RATES])

    run("Matching sensitivity",
        [py, "dbt/portfolio_matching_sensitivity.py", "--with-hvac", "--seed", str(SEED)])

    run("Report 2 figures", [py, "report-2/make_berdo_figures.py"])

    if not args.no_report:
        typst = shutil.which("typst")
        if typst is None:
            print("\n== Report 2: typst not found, skipped")
        else:
            run("Report 2", [typst, "compile", "--root", ".", "report-2/report 2.typ"])

    print("\nDone. Review the changes with `git diff --stat`.")


if __name__ == "__main__":
    main()
