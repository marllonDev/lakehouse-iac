-- A user's next session must start after the previous one ended.
with ordered as (
    select
        user_id,
        session_number,
        session_start,
        lag(session_end) over (partition by user_id order by session_number) as previous_end
    from {{ ref('int_wb__sessions') }}
)

select * from ordered where previous_end is not null and session_start < previous_end
