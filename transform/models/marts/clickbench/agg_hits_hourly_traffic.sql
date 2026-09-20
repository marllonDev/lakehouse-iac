select
    event_date,
    hour(event_at)                                      as event_hour,
    count(*)                                            as events,
    count(distinct user_id)                             as users

from {{ ref('int_hits__events') }}
group by event_date, hour(event_at)
