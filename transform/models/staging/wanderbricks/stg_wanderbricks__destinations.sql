with source as (

    select * from {{ source('wanderbricks', 'destinations') }}

),

renamed as (

    select
        destination_id,
        destination,
        country,
        state_or_province,
        state_or_province_code,
        description

    from source

)

select * from renamed
