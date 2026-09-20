with ordered as (

    select *, lag(event_at) over (partition by user_id order by event_at) as previous_event_at
    from {{ ref('int_wb__user_events') }}
    where user_id is not null

),

flagged as (

    select
        *,
        case
            when previous_event_at is null then 1
            when unix_timestamp(event_at) - unix_timestamp(previous_event_at) > 1800 then 1
            else 0
        end as starts_session
    from ordered

),

numbered as (

    select
        *,
        sum(starts_session) over (
            partition by user_id order by event_at
            rows between unbounded preceding and current row
        ) as session_number
    from flagged

)

select
    user_id,
    session_number,
    concat(cast(user_id as string), '-', cast(session_number as string))          as session_id,
    min(event_at)                                                                  as session_start,
    max(event_at)                                                                  as session_end,
    count(*)                                                                       as events,
    count(distinct property_id)                                                    as properties_seen,
    sum(case when event_type = 'search' then 1 else 0 end)                         as searches

from numbered
group by user_id, session_number
