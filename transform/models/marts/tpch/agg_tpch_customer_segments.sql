select
    market_segment,
    count(*)                                            as customers,
    sum(orders)                                         as orders,
    sum(total_ordered)                                  as total_ordered,
    avg(total_ordered)                                  as avg_customer_value

from {{ ref('dim_tpch_customer_value') }}
group by market_segment
