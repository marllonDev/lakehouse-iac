select
    view_id, user_id, property_id, `timestamp` as viewed_at, device_type, page_url, referrer

from {{ ref('stg_wanderbricks__page_views') }}
qualify row_number() over (partition by view_id order by `timestamp` desc) = 1
