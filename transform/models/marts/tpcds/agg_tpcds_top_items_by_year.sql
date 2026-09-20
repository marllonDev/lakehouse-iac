with ranked as (

    select
        year,
        item_sk,
        sum(ext_sales_price)                                                            as revenue,
        row_number() over (partition by year order by sum(ext_sales_price) desc)         as revenue_rank
    from {{ ref('fct_tpcds_sales') }}
    group by year, item_sk

)

select * from ranked where revenue_rank <= 100
