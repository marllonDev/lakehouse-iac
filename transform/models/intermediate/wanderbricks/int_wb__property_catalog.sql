with amenities as (

    select property_id, count(*) as amenity_count
    from {{ ref('stg_wanderbricks__property_amenities') }}
    group by property_id

)

select
    p.property_id, p.host_id, p.destination_id, p.title, p.property_type, p.base_price,
    p.max_guests, p.bedrooms, p.bathrooms, p.property_latitude, p.property_longitude, p.created_at,
    h.name                          as host_name,
    h.is_verified                   as host_verified,
    h.rating                        as host_rating,
    d.destination,
    d.country                       as destination_country,
    coalesce(a.amenity_count, 0)    as amenity_count

from {{ ref('stg_wanderbricks__properties') }} p
left join {{ ref('stg_wanderbricks__hosts') }} h         on p.host_id = h.host_id
left join {{ ref('stg_wanderbricks__destinations') }} d  on p.destination_id = d.destination_id
left join amenities a                                    on p.property_id = a.property_id
