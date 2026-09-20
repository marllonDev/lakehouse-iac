with source as (

    select * from {{ source('wanderbricks', 'reviews') }}

),

renamed as (

    select
        booking_id,
        comment,
        created_at,
        is_deleted,
        property_id,
        rating,
        review_id,
        updated_at,
        user_id

    from source

)

select * from renamed
