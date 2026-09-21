select
    b.host_id,
    count(*)                                                                            as bookings,
    sum(case when b.status <> 'cancelled' then b.total_amount else 0 end)               as revenue,
    avg(case when b.status <> 'cancelled' then b.total_amount end)                      as avg_booking_value,
    count(distinct b.property_id)                                                       as properties_booked

from {{ ref('fct_wb_bookings') }} b
where b.host_id is not null
group by b.host_id
