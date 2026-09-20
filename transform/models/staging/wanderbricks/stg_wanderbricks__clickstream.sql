with source as (

    select * from {{ source('wanderbricks', 'clickstream') }}

),

renamed as (

    select
        event,
        metadata,
        property_id,
        timestamp,
        user_id

    from source

)

select * from renamed
