# Is the Cheapest Retrofit Compliant? Estimating BERDO Retrofit Costs for Boston Office Buildings

DS5500 Data Science Capstone, Northeastern University

**Authors:** Konstantinos Theodoropoulos, Zachary Wegrzyniak, Kateryna Lysytsyna

**Industry Stakeholder:** Debra Shepard, Founder & Principal Consultant, Riverstone Sustainability

## Summary

Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) requires large buildings to report their energy consumption every year and comply with increasingly strict greenhouse gas emissions limits, reaching net zero by 2050. For building owners, meeting these requirements presents a financial challenge: determining which decarbonization investments can sufficiently reduce emissions while minimizing long-term costs.

This project investigates cost-effective decarbonization strategies for Boston office buildings using BERDO disclosures, ComStock building energy simulations, and Buildings Technology Baseline (BTB) installation cost data. By matching real buildings with representative simulations, we estimate the emissions reductions and installation costs of 23 retrofit options. We then compare their projected 20-year costs from 2027 to 2046, in 2025 dollars, accounting for energy expenses, and either BERDO's Alternative Compliance Payments (ACP) or the societal cost of greenhouse gas emissions.

Our integrated analysis includes 297 matched office buildings, of which 81 are projected to exceed the 2030 BERDO emissions standard under the city's projected electricity emissions factor. Among these 81 buildings, 71 have at least one modeled retrofit option capable of achieving compliance. However, the lowest-cost option achieves compliance for only 35 buildings from the owner's perspective and 46 when accounting for societal climate damages. These findings highlight the trade-offs between financial incentives and emissions reduction goals, as well as the importance of evaluating retrofit investments on a building-specific basis.

Future work will focus on improving data completeness, validating building-matching accuracy and retrofit cost estimates, and refining the analysis to provide more reliable decarbonization investment recommendations.

## Project Materials

- Latest Presentation: [`presentation-2/slides.typ`](presentation-2/slides.typ)
- Latest Report: [`report-2/report 2.typ`](report-2/report%202.typ)

The original project proposal is available in [`report/proposal.typ`](report/proposal.typ).

## Building the Project

You need [uv](https://docs.astral.sh/uv/), which installs Python 3.14 and the locked packages, [Typst](https://typst.app/) (tested with 0.15.1), and an internet connection. The BERDO disclosure and the grid and price scenario sources are in [`data/raw`](data/raw/SOURCES.md). The ComStock simulations, the BTB cost data, and the City of Boston building and parcel data are downloaded during the build.

```sh
git clone https://github.com/wegry/DS5500.git
cd DS5500
uv sync
uv run python dbt/regenerate.py
```

[`dbt/regenerate.py`](dbt/regenerate.py) rebuilds everything in order and stops at the first failure:

1. `dbt build` loads the data into DuckDB (`dbt/ds5500.duckdb`), runs the models and their tests, and writes the analysis CSVs to `dbt/analysis_outputs/`.
2. The 20-year Monte Carlo, first a zero-uncertainty check against dbt, then 5,000 draws (seed 5500).
3. The matching sensitivity tables in the Report 2 appendix (`dbt/portfolio_matching_sensitivity.py`).
4. The Report 2 figures (`report-2/make_berdo_figures.py`), then the report itself, compiled to `report-2/report 2.pdf`.

Pass `--no-report` to skip compiling the report. To compile only the report from the tracked outputs, run this from the repository root:

```sh
typst compile --root . "report-2/report 2.typ"
```
