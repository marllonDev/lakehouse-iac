with source as (

    select * from {{ source('tpcds', 'ship_mode') }}

),

renamed as (

    select
        sm_ship_mode_sk as ship_mode_sk,
        sm_ship_mode_id as ship_mode_id,
        sm_type as type,
        sm_code as code,
        sm_carrier as carrier,
        sm_contract as contract

    from source

)

select * from renamed
