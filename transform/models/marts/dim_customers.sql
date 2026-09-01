{{ config(materialized='table') }}

with customers as (

    select * from {{ ref('stg_customers') }}

),

nations as (

    select * from {{ ref('stg_nations') }}

),

regions as (

    select * from {{ ref('stg_regions') }}

),

joined as (

    select
        customers.customer_key,
        customers.customer_name,
        customers.market_segment,
        customers.account_balance,
        customers.phone_number,
        nations.nation_name,
        regions.region_name

    from customers
    left join nations on customers.nation_key = nations.nation_key
    left join regions on nations.region_key = regions.region_key

)

select * from joined
