with revenue as (

    select
        destination_id,
        property_id,
        sum(case when status <> 'cancelled' then total_amount else 0 end)               as revenue
    from {{ ref('fct_wb_bookings') }}
    where destination_id is not null
    group by destination_id, property_id

),

ranked as (

    select *, row_number() over (partition by destination_id order by revenue desc) as revenue_rank
    from revenue

)

select * from ranked where revenue_rank <= 10
