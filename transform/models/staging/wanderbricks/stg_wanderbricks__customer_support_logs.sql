with source as (

    select * from {{ source('wanderbricks', 'customer_support_logs') }}

),

renamed as (

    select
        created_at,
        messages,
        support_agent_id,
        ticket_id,
        user_id

    from source

)

select * from renamed
