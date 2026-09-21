select
    review_id, booking_id, property_id, user_id, rating, comment, created_at

from {{ ref('stg_wanderbricks__reviews') }}
where not coalesce(is_deleted, false)
qualify row_number() over (partition by review_id order by updated_at desc) = 1
