select
    cast(session_start as date)                                                     as session_date,
    count(*)                                                                        as sessions,
    avg(events)                                                                     as avg_events,
    avg(unix_timestamp(session_end) - unix_timestamp(session_start))                as avg_duration_seconds,
    sum(searches)                                                                   as searches

from {{ ref('int_wb__sessions') }}
group by cast(session_start as date)
