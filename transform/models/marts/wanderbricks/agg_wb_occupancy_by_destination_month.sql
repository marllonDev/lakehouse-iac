select
    date_trunc('month', check_in)                                                       as stay_month,
    destination_id,
    destination,
    count(*)                                                                            as bookings,
    sum(case when status <> 'cancelled' then nights else 0 end)                         as nights_booked,
    sum(case when status <> 'cancelled' then total_amount else 0 end)                   as revenue,
    sum(case when status = 'cancelled' then 1 else 0 end)                               as cancellations

from {{ ref('fct_wb_bookings') }}
where destination_id is not null
group by date_trunc('month', check_in), destination_id, destination
