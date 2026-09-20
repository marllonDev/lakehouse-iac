with source as (

    select * from {{ source('wanderbricks', 'property_amenities') }}

),

renamed as (

    select
        property_id,
        amenity_id

    from source

)

select * from renamed
