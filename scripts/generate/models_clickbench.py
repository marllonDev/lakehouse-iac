"""ClickBench models: about 100 million web analytics events.

These are the heavy aggregations of the project, so they show how each engine
copes when the warehouse, not dbt, does most of the work.
"""

from lib import Model, at_least, between, merge, not_null, write_group


def intermediate():
    return [
        Model(
            "int_hits__events",
            """
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
""",
            "Page views that were not refreshes, with the flags spelled as booleans and the host of the page pulled out.",
        ),
        Model(
            "int_hits__daily_users",
            """
select
    event_date,
    counter_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users,
    sum(case when has_search_phrase then 1 else 0 end)  as searches

from {{ ref('int_hits__events') }}
group by event_date, counter_id
""",
            "Events, visitors and searches of each site on each day.",
        ),
    ]


def marts():
    return [
        Model(
            "fct_hits_daily",
            "select * from {{ ref('int_hits__daily_users') }}",
            "One row per site and day.",
            grain=("event_date", "counter_id"),
            tests=merge(not_null("event_date", "counter_id"), {"events": [at_least(1)]}),
        ),
        Model(
            "agg_hits_top_search_phrases",
            """
select
    search_phrase,
    count(*)                                            as searches,
    count(distinct user_id)                             as users

from {{ ref('int_hits__events') }}
where has_search_phrase
group by search_phrase
order by searches desc
limit 1000
""",
            "The thousand most searched phrases.",
            grain=("search_phrase",),
            tests=not_null("search_phrase"),
        ),
        Model(
            "agg_hits_by_region",
            """
select
    region_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users,
    avg(resolution_width)                               as avg_resolution_width,
    avg(case when is_mobile_device then 1.0 else 0.0 end) as mobile_share

from {{ ref('int_hits__events') }}
group by region_id
""",
            "Traffic, audience and mobile share of each region.",
            grain=("region_id",),
            tests=merge(not_null("region_id"), {"mobile_share": [between(0, 1)]}),
        ),
        Model(
            "agg_hits_by_engine",
            """
select
    search_engine_id,
    adv_engine_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users

from {{ ref('int_hits__events') }}
group by search_engine_id, adv_engine_id
""",
            "Traffic that came from each search engine and advertising engine.",
            grain=("search_engine_id", "adv_engine_id"),
            tests=not_null("search_engine_id", "adv_engine_id"),
        ),
        Model(
            "agg_hits_devices",
            """
select
    is_mobile_device,
    mobile_phone_model,
    os_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users

from {{ ref('int_hits__events') }}
group by is_mobile_device, mobile_phone_model, os_id
""",
            "Traffic by the kind of device and operating system.",
            grain=("is_mobile_device", "mobile_phone_model", "os_id"),
            tests=not_null("is_mobile_device"),
        ),
        Model(
            "agg_hits_top_hosts",
            """
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
""",
            "The thousand busiest hosts and how many visitors stayed.",
            grain=("url_host",),
            tests=merge(not_null("url_host"), {"engaged_share": [between(0, 1)]}),
        ),
        Model(
            "agg_hits_hourly_traffic",
            """
select
    event_date,
    hour(event_at)                                      as event_hour,
    count(*)                                            as events,
    count(distinct user_id)                             as users

from {{ ref('int_hits__events') }}
group by event_date, hour(event_at)
""",
            "Events and visitors for each hour of each day.",
            grain=("event_date", "event_hour"),
            tests=merge(not_null("event_date", "event_hour"), {"event_hour": [between(0, 23)]}),
        ),
        Model(
            "agg_hits_traffic_sources",
            """
select
    traffic_source_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users,
    avg(case when is_engaged then 1.0 else 0.0 end)     as engaged_share

from {{ ref('int_hits__events') }}
group by traffic_source_id
""",
            "Where the traffic came from and whether it stayed.",
            grain=("traffic_source_id",),
            tests=merge(not_null("traffic_source_id"), {"engaged_share": [between(0, 1)]}),
        ),
    ]


def generate():
    n = write_group("intermediate/clickbench", "_int_clickbench__models.yml", intermediate())
    n += write_group("marts/clickbench", "_clickbench__models.yml", marts())
    return n
