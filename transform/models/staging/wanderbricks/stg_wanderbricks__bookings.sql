with source as (

    select * from {{ source('wanderbricks', 'bookings') }}

),

renamed as (

    select
        booking_id,
        user_id,
        property_id,
        check_in,
        check_out,
        guests_count,
        total_amount,
        status,
        created_at,
        updated_at

    from source

)

select * from renamed
