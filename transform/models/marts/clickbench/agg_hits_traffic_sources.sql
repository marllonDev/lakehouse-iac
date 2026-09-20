select
    traffic_source_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users,
    avg(case when is_engaged then 1.0 else 0.0 end)     as engaged_share

from {{ ref('int_hits__events') }}
group by traffic_source_id
