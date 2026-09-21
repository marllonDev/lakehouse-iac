select
    customer_sk,
    min(calendar_date)                                        as first_purchase_date,
    max(calendar_date)                                        as last_purchase_date,
    count(distinct order_id)                                  as orders,
    sum(ext_sales_price)                                      as revenue,
    sum(net_profit)                                           as profit,
    percent_rank() over (order by sum(ext_sales_price))       as revenue_percentile

from {{ ref('fct_tpcds_sales') }}
where customer_sk is not null
group by customer_sk
