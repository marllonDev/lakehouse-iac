select
    date_trunc('month', created_at)                                                 as booking_month,
    count(*)                                                                        as bookings,
    sum(case when status = 'cancelled' then 1 else 0 end)                           as cancelled,
    sum(case when status = 'cancelled' then 1 else 0 end) / count(*)                as cancellation_rate

from {{ ref('fct_wb_bookings') }}
group by date_trunc('month', created_at)
