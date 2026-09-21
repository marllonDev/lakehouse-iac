select
    search_engine_id,
    adv_engine_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users

from {{ ref('int_hits__events') }}
group by search_engine_id, adv_engine_id
