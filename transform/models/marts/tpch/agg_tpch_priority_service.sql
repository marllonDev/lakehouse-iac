select
    order_priority,
    count(distinct order_key)                           as orders,
    avg(days_to_ship)                                   as avg_days_to_ship,
    avg(case when is_late then 1.0 else 0.0 end)        as late_share

from {{ ref('fct_tpch_order_lines') }}
group by order_priority
