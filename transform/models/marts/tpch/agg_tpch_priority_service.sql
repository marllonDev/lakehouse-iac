select
    f.order_priority,
    w.priority_weight,
    count(distinct f.order_key)                         as orders,
    count(distinct f.order_key) * w.priority_weight     as weighted_orders,
    avg(f.days_to_ship)                                 as avg_days_to_ship,
    avg(case when f.is_late then 1.0 else 0.0 end)      as late_share

from {{ ref('fct_tpch_order_lines') }} f
left join {{ ref('seed_tpch_priority_weights') }} w on f.order_priority = w.order_priority
group by f.order_priority, w.priority_weight
