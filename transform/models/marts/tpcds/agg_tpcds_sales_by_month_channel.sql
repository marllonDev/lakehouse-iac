with monthly as (

    select
        year, month, channel,
        sum(ext_sales_price)          as revenue,
        sum(net_profit)               as profit,
        sum(quantity)                 as units,
        count(distinct order_id)      as orders
    from {{ ref('fct_tpcds_sales') }}
    group by year, month, channel

)

select
    *,
    sum(revenue) over (partition by channel, year order by month)                        as ytd_revenue,
    revenue / nullif(sum(revenue) over (partition by year, month), 0)                    as channel_share

from monthly
