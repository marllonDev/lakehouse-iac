select
    channel,
    case
        when sales_price < 10  then '1 under 10'
        when sales_price < 50  then '2 10 to 50'
        when sales_price < 100 then '3 50 to 100'
        when sales_price < 200 then '4 100 to 200'
        else '5 200 and over'
    end                                                                 as price_band,
    sum(quantity)                                                       as units,
    sum(ext_sales_price)                                                as revenue,
    avg(discount_amount / nullif(ext_list_price, 0))                    as avg_discount_rate

from {{ ref('fct_tpcds_sales') }}
where sales_price is not null
group by channel, 2
