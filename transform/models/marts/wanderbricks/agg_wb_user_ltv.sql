select
    user_id,
    count(*)                                                                            as bookings,
    sum(case when status <> 'cancelled' then total_amount else 0 end)                   as total_spend,
    min(created_at)                                                                     as first_booking_at,
    max(created_at)                                                                     as last_booking_at,
    ntile(10) over (order by sum(case when status <> 'cancelled' then total_amount else 0 end)) as spend_decile

from {{ ref('fct_wb_bookings') }}
where user_id is not null
group by user_id
