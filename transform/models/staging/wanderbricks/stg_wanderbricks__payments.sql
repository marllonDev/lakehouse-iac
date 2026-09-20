with source as (

    select * from {{ source('wanderbricks', 'payments') }}

),

renamed as (

    select
        payment_id,
        booking_id,
        amount,
        payment_method,
        status,
        payment_date

    from source

)

select * from renamed
