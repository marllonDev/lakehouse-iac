with source as (

    select * from {{ source('wanderbricks', 'property_images') }}

),

renamed as (

    select
        image_id,
        property_id,
        url,
        sequence,
        is_primary,
        uploaded_at

    from source

)

select * from renamed
