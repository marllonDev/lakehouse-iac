select
    region_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users,
    avg(resolution_width)                               as avg_resolution_width,
    avg(case when is_mobile_device then 1.0 else 0.0 end) as mobile_share

from {{ ref('int_hits__events') }}
group by region_id
