with source as (

    select * from {{ source('wanderbricks', 'users') }}

),

renamed as (

    select
        user_id,
        email,
        name,
        country,
        user_type,
        created_at,
        is_business,
        company_name

    from source

)

select * from renamed
