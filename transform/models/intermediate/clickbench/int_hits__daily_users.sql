select
    event_date,
    counter_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users,
    sum(case when has_search_phrase then 1 else 0 end)  as searches

from {{ ref('int_hits__events') }}
group by event_date, counter_id
