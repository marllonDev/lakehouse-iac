select
    channel,
    day_name,
    is_weekend,
    count(distinct order_id)        as orders,
    sum(ext_sales_price)            as revenue

from {{ ref('fct_tpcds_sales') }}
group by channel, day_name, is_weekend
