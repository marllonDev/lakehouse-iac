select
    ship_mode,
    count(*)                                            as lines,
    avg(days_to_ship)                                   as avg_days_to_ship,
    avg(case when is_late then 1.0 else 0.0 end)        as late_share,
    sum(net_amount)                                     as net_revenue

from {{ ref('fct_tpch_order_lines') }}
group by ship_mode
