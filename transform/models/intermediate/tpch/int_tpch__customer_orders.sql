select
    customer_key,
    count(*)                                        as orders,
    sum(order_total)                                as total_ordered,
    min(ordered_at)                                 as first_ordered_at,
    max(ordered_at)                                 as last_ordered_at,
    sum(case when order_status = 'open' then 1 else 0 end) as open_orders

from {{ ref('stg_orders') }}
group by customer_key
