select
    watch_id, event_at, event_date, counter_id, user_id, region_id, client_ip,
    url, referer, search_phrase, mobile_phone_model,
    os_id, user_agent_id, resolution_width, search_engine_id, adv_engine_id, traffic_source_id,
    is_mobile = 1                                       as is_mobile_device,
    is_refresh = 1                                      as is_page_refresh,
    is_not_bounce = 1                                   as is_engaged,
    search_phrase <> ''                                 as has_search_phrase,
    nullif(regexp_extract(url, '^(?:https?://)?([^/?#]+)', 1), '')    as url_host

from {{ ref('stg_clickbench__hits') }}
where is_refresh = 0
