with source as (

    select * from {{ source('wanderbricks', 'page_views') }}

),

renamed as (

    select
        device_type,
        page_url,
        property_id,
        referrer,
        timestamp,
        user_id,
        view_id

    from source

)

select * from renamed
