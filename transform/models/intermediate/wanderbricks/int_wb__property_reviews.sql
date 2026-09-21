select
    property_id,
    count(*)                    as review_count,
    avg(rating)                 as avg_rating,
    min(rating)                 as min_rating,
    max(rating)                 as max_rating,
    max(created_at)             as last_review_at

from {{ ref('stg_wanderbricks__reviews') }}
where not coalesce(is_deleted, false)
group by property_id
