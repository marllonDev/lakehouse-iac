select
    d.destination_id, d.destination, d.country, d.state_or_province,
    count(p.property_id)      as properties

from {{ ref('stg_wanderbricks__destinations') }} d
left join {{ ref('stg_wanderbricks__properties') }} p on d.destination_id = p.destination_id
group by d.destination_id, d.destination, d.country, d.state_or_province
