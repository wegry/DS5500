# Optimizing Decarbonization Investment Decisions for Boston Office Buildings

DS5500 Data Science Capstone, Northeastern University

**Authors:** Konstantinos Theodoropoulos, Zachary Wegrzyniak, Kateryna Lysytsyna

**Sponsor / stakeholders:** Konstantinos Theodoropoulos

## Summary

Boston's Building Emissions Reduction and Disclosure Ordinance (BERDO) requires large buildings to report their energy use every year and to meet emissions limits that step down over time, reaching net zero by 2050. For each building, there are more candidate retrofit projects (heat pumps, envelope upgrades, LED lighting, rooftop solar, switching off fuel oil) than the available capital allows for. The usual approach ranks projects by cost per ton of CO2 avoided and funds them from the cheapest down. That treats projects as independent and every year as the same, and neither is true.

This project aims to identify cost-effective decarbonization options for Boston office buildings by considering BERDO disclosures, ComStock building simulations, and Buildings Technology Baseline (BTB) installation cost data. Preliminary exploration has revealed 290 buildings containing office space with reported emissions intensity, of which 96 currently exceed the 2030 emissions standard. A data integration pipeline was developed to match BERDO buildings with representative ComStock simulations and estimate potential retrofit emissions reductions. Ongoing work focuses on integrating installation costs and optimizing the selection of one of four retrofit packages or Alternative Compliance Payments (ACP) over the 2030-2034 period. The resulting framework aims to support investment decisions for office buildings by balancing emissions reductions, compliance requirements, and budget constraints.

The full proposal source is in [`report/proposal.typ`](report/proposal.typ).
