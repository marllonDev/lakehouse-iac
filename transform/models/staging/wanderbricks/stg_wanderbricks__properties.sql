with source as (

    select * from {{ source('wanderbricks', 'properties') }}

),

renamed as (

    select
        property_id,
        host_id,
        destination_id,
        title,
        description,
        base_price,
        property_type,
        max_guests,
        bedrooms,
        bathrooms,
        property_latitude,
        property_longitude,
        created_at

    from source

)

select * from renamed
