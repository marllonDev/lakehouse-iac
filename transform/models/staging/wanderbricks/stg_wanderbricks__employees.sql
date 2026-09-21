with source as (

    select * from {{ source('wanderbricks', 'employees') }}

),

renamed as (

    select
        employee_id,
        host_id,
        name,
        role,
        email,
        phone,
        country,
        joined_at,
        end_service_date,
        is_currently_employed

    from source

)

select * from renamed
