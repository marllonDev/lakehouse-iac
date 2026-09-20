with source as (

    select * from {{ source('wanderbricks', 'countries') }}

),

renamed as (

    select
        country,
        country_code,
        continent

    from source

)

select * from renamed
