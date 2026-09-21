select
    url_host,
    count(*)                                            as events,
    count(distinct user_id)                             as users,
    avg(case when is_engaged then 1.0 else 0.0 end)     as engaged_share

from {{ ref('int_hits__events') }}
where url_host is not null
group by url_host
order by events desc
limit 1000
