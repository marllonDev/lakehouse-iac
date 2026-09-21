select
    coalesce(cast(s.promo_sk as string), 'none')                       as promo,
    count(distinct s.order_id)                                         as orders,
    sum(s.quantity)                                                    as units,
    sum(s.ext_sales_price)                                             as revenue,
    sum(s.discount_amount) / nullif(sum(s.ext_list_price), 0)          as discount_rate

from {{ ref('fct_tpcds_sales') }} s
group by coalesce(cast(s.promo_sk as string), 'none')
