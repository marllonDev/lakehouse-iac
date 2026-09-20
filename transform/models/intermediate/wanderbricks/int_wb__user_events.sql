select 'page_view' as event_type, user_id, property_id, `timestamp` as event_at,
       device_type as device, page_url as detail
from {{ ref('stg_wanderbricks__page_views') }}

union all

select event, user_id, property_id, `timestamp`, metadata.device, metadata.referrer
from {{ ref('stg_wanderbricks__clickstream') }}
