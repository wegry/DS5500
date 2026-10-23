# Optimizing Corporate Decarbonization Investments: Which Projects to Fund, and in What Year

DS5500 Data Science Capstone, Northeastern University

**Authors:** Konstantinos Theodoropoulos, Zachary Wegrzyniak, Kateryna Lysytsyna

**Sponsor / stakeholders:** TODO

## Summary

Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) requires large buildings to report their energy use every year and to meet emissions limits that step down over time, reaching net zero by 2050. A university with many such buildings has more candidate retrofit projects (heat pumps, envelope upgrades, LED lighting, rooftop solar, switching off fuel oil) than it has capital. The usual approach ranks projects by cost per ton of CO2 avoided and funds them from the cheapest down. That treats projects as independent and every year as the same, and neither is true.

We are building a decision-support tool for university and college building owners in Boston that chooses which projects to fund and in which year, given annual capital limits and each building's BERDO compliance schedule. We compare its multi-year roadmap against the cost-ranking baseline on the same buildings. The main dataset is the 2026 BERDO disclosure of about 5,600 Boston buildings, combined with public data on retrofit performance (ComStock), technology costs (NLR ATB), energy prices (EIA AEO), and grid emissions (Cambium, EPA eGRID).

The full proposal source is in [`report/proposal.typ`](report/proposal.typ).
