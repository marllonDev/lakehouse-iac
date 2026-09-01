with source as (

    select * from {{ source('tpch', 'lineitem') }}

),

renamed as (

    select
        -- lineitem has no natural single-column key; the grain is the order
        -- plus the line number within it.
        {{ dbt_utils.generate_surrogate_key(['l_orderkey', 'l_linenumber']) }} as order_line_key,

        l_orderkey      as order_key,
        l_linenumber    as line_number,
        l_partkey       as part_key,
        l_suppkey       as supplier_key,
        l_quantity      as quantity,
        l_extendedprice as gross_amount,
        l_discount      as discount_rate,
        l_tax           as tax_rate,
        l_shipdate      as shipped_at,
        l_commitdate    as committed_at,
        l_receiptdate   as received_at,
        l_shipmode      as ship_mode,
        l_returnflag    as return_flag,

        l_extendedprice * (1 - l_discount)            as net_amount,
        l_extendedprice * (1 - l_discount) * (1 + l_tax) as net_amount_with_tax

    from source

)

select * from renamed
