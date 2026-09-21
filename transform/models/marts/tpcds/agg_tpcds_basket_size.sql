with baskets as (

    select
        channel, year, month, order_id,
        count(*)                       as items,
        sum(ext_sales_price)           as basket_value
    from {{ ref('fct_tpcds_sales') }}
    group by channel, year, month, order_id

)

select
    channel, year, month,
    count(*)                                        as orders,
    avg(items)                                      as avg_items,
    percentile_approx(items, 0.5)                   as median_items,
    avg(basket_value)                               as avg_basket_value,
    max(basket_value)                               as max_basket_value

from baskets
group by channel, year, month
