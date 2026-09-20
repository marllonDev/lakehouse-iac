select
    b.booking_id, b.user_id, b.property_id, b.check_in, b.check_out, b.guests_count,
    b.total_amount, b.status, b.created_at, b.updated_at,
    datediff(b.check_out, b.check_in)        as nights,
    p.host_id,
    p.destination_id,
    p.property_type,
    p.base_price,
    p.bedrooms,
    d.destination,
    d.country                                as destination_country,
    d.state_or_province,
    u.country                                as user_country,
    u.user_type

from {{ ref('stg_wanderbricks__bookings') }} b
left join {{ ref('stg_wanderbricks__properties') }} p   on b.property_id = p.property_id
left join {{ ref('stg_wanderbricks__destinations') }} d on p.destination_id = d.destination_id
left join {{ ref('stg_wanderbricks__users') }} u        on b.user_id = u.user_id
