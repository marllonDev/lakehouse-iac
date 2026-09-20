with sold as (

    select item_sk, sum(quantity) as units_sold
    from {{ ref('fct_tpcds_sales') }}
    group by item_sk

),

returned as (

    select item_sk, sum(return_quantity) as units_returned
    from {{ ref('fct_tpcds_returns') }}
    group by item_sk

)

select
    sold.item_sk,
    sold.units_sold,
    coalesce(returned.units_returned, 0)                                                as units_returned,
    coalesce(returned.units_returned, 0) / nullif(sold.units_sold, 0)                   as return_rate

from sold
left join returned on sold.item_sk = returned.item_sk
where sold.units_sold > 0
