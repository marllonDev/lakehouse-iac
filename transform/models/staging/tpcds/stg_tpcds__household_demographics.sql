with source as (

    select * from {{ source('tpcds', 'household_demographics') }}

),

renamed as (

    select
        hd_demo_sk as demo_sk,
        hd_income_band_sk as income_band_sk,
        hd_buy_potential as buy_potential,
        hd_dep_count as dep_count,
        hd_vehicle_count as vehicle_count

    from source

)

select * from renamed
