with stock as (

    select year, month, category, avg(quantity_on_hand) as avg_on_hand
    from {{ ref('fct_tpcds_inventory') }}
    where category is not null
    group by year, month, category

),

sold as (

    select s.year, s.month, i.category, sum(s.quantity) as units_sold
    from {{ ref('fct_tpcds_sales') }} s
    join {{ ref('dim_tpcds_item') }} i on s.item_sk = i.item_sk
    where i.category is not null
    group by s.year, s.month, i.category

)

select
    stock.year, stock.month, stock.category,
    stock.avg_on_hand,
    sold.units_sold,
    sold.units_sold / nullif(stock.avg_on_hand, 0)      as turnover

from stock
join sold on stock.year = sold.year and stock.month = sold.month and stock.category = sold.category
