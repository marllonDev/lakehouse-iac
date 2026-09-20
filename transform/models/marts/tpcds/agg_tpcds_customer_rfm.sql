with customer_activity as (

    select
        customer_sk,
        max(calendar_date)                  as last_purchase_date,
        count(distinct order_id)            as frequency,
        sum(ext_sales_price)                as monetary
    from {{ ref('fct_tpcds_sales') }}
    where customer_sk is not null
    group by customer_sk

),

with_recency as (

    select
        *,
        datediff((select max(calendar_date) from {{ ref('fct_tpcds_sales') }}), last_purchase_date) as recency_days
    from customer_activity

)

select
    *,
    ntile(5) over (order by recency_days desc)     as recency_score,
    ntile(5) over (order by frequency)             as frequency_score,
    ntile(5) over (order by monetary)              as monetary_score

from with_recency
