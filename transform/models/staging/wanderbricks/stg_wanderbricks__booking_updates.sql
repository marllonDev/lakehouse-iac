with source as (

    select * from {{ source('wanderbricks', 'booking_updates') }}

),

renamed as (

    select
        booking_id,
        booking_update_id,
        check_in,
        check_out,
        created_at,
        guests_count,
        property_id,
        status,
        total_amount,
        updated_at,
        user_id

    from source

)

select * from renamed
