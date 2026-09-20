with source as (

    select * from {{ source('wanderbricks', 'amenities') }}

),

renamed as (

    select
        amenity_id,
        name,
        category,
        icon

    from source

)

select * from renamed
