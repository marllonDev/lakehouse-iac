select
    h.host_id,
    h.name,
    h.is_verified,
    h.is_active,
    h.rating,
    h.country,
    h.joined_at,
    count(p.property_id)          as properties,
    avg(p.base_price)             as avg_base_price,
    sum(p.bedrooms)               as total_bedrooms

from {{ ref('stg_wanderbricks__hosts') }} h
left join {{ ref('stg_wanderbricks__properties') }} p on h.host_id = p.host_id
group by h.host_id, h.name, h.is_verified, h.is_active, h.rating, h.country, h.joined_at
