{{ config(materialized='table') }}

with orders as (

    select * from {{ ref('fct_orders') }}

),

customers as (

    select * from {{ ref('dim_customers') }}

),

joined as (

    select
        orders.ordered_at_month,
        customers.region_name,
        customers.market_segment,
        orders.net_amount,
        orders.order_key

    from orders
    inner join customers on orders.customer_key = customers.customer_key

)

select
    ordered_at_month,
    region_name,
    market_segment,
    count(distinct order_key) as order_count,
    sum(net_amount)           as net_revenue,
    avg(net_amount)           as avg_order_value

from joined
group by ordered_at_month, region_name, market_segment
