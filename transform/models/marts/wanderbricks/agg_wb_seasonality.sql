select
    month(check_in)                                         as check_in_month,
    property_type,
    count(*)                                                as bookings,
    avg(total_amount / nullif(nights, 0))                   as avg_price_per_night

from {{ ref('fct_wb_bookings') }}
where property_type is not null
group by month(check_in), property_type
