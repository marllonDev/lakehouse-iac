with source as (

    select * from {{ source('wanderbricks', 'hosts') }}

),

renamed as (

    select
        host_id,
        name,
        email,
        phone,
        is_verified,
        is_active,
        rating,
        country,
        joined_at

    from source

)

select * from renamed
