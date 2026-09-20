select
    c.customer_key, c.customer_name, c.market_segment, c.nation_name, c.region_name,
    coalesce(o.orders, 0)               as orders,
    coalesce(o.total_ordered, 0)        as total_ordered,
    o.first_ordered_at,
    o.last_ordered_at

from {{ ref('dim_customers') }} c
left join {{ ref('int_tpch__customer_orders') }} o on c.customer_key = o.customer_key
