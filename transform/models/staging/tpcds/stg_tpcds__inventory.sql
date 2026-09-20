with source as (

    select * from {{ source('tpcds', 'inventory') }}

),

renamed as (

    select
        inv_date_sk as date_sk,
        inv_item_sk as item_sk,
        inv_warehouse_sk as warehouse_sk,
        inv_quantity_on_hand as quantity_on_hand

    from source

)

select * from renamed
