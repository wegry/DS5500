
-- Evaluate how the number of ComStock neighbors
-- affects predicted emissions and BERDO compliance.
-- Compare k = 1, 3, 5 against the existing k = 10 model.

with comparisons as (
    select
        s.berdo_id,
        s.upgrade_id,
        s.k,

        abs(
            s.ghg_reduction_pct - b.ghg_reduction_pct
        ) * 100 as reduction_difference_pp,

        s.meets_standard_after
            is distinct from b.meets_standard_after
            as compliance_changed

    from {{ ref('berdo_matching_k_sensitivity') }} s

    inner join {{ ref('berdo_matching_k_sensitivity') }} b
        on s.berdo_id = b.berdo_id
        and s.upgrade_id = b.upgrade_id
        and b.k = 10

    where s.k in (1, 3, 5)
)

select
    k,
    count(*) as scenarios,

    round(avg(reduction_difference_pp), 2)
        as mean_difference_pp,

    round(median(reduction_difference_pp), 2)
        as median_difference_pp,

    round(max(reduction_difference_pp), 2)
        as max_difference_pp,

    count(*) filter (
        where compliance_changed
    ) as compliance_changes,

    count(distinct berdo_id) filter (
        where compliance_changed
    ) as affected_buildings

from comparisons
group by k
order by k
