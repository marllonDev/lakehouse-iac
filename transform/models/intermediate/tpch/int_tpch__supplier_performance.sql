select
    supplier_key,
    count(*)                                        as lines_supplied,
    sum(quantity)                                   as units_supplied,
    sum(net_amount)                                 as net_revenue,
    avg(days_to_ship)                               as avg_days_to_ship,
    avg(case when is_late then 1.0 else 0.0 end)    as late_share

from {{ ref('int_tpch__order_lines_enriched') }}
group by supplier_key
