with source as (

    select * from {{ source('tpch', 'orders') }}

),

renamed as (

    select
        o_orderkey      as order_key,
        o_custkey       as customer_key,
        o_orderdate     as ordered_at,
        o_totalprice    as order_total,
        o_orderpriority as order_priority,
        o_shippriority  as ship_priority,
        o_clerk         as clerk_id,

        -- TPC-H encodes status as a single letter; spell it out once here so no
        -- downstream model has to remember what 'F' means.
        case o_orderstatus
            when 'O' then 'open'
            when 'F' then 'fulfilled'
            when 'P' then 'partial'
        end as order_status

    from source

)

select * from renamed
