select
    i.category,
    s.year,
    sum(s.ext_sales_price)                                                              as revenue,
    sum(s.net_profit)                                                                   as profit,
    sum(s.quantity)                                                                     as units,
    rank() over (partition by s.year order by sum(s.ext_sales_price) desc)              as revenue_rank

from {{ ref('fct_tpcds_sales') }} s
join {{ ref('dim_tpcds_item') }} i on s.item_sk = i.item_sk
where i.category is not null
group by i.category, s.year
