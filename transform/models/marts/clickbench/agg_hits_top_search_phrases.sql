select
    search_phrase,
    count(*)                                            as searches,
    count(distinct user_id)                             as users

from {{ ref('int_hits__events') }}
where has_search_phrase
group by search_phrase
order by searches desc
limit 1000
