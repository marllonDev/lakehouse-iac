select
    date_trunc('month', shipped_at)                     as ship_month,
    count(*)                                            as lines,
    sum(case when is_late then 1 else 0 end)            as late_lines,
    avg(days_late)                                      as avg_days_late

from {{ ref('fct_tpch_order_lines') }}
group by date_trunc('month', shipped_at)
