{{ config(materialized='table') }}

with edits as (

    select * from {{ ref('fct_wikipedia_edits') }}

)

select
    edited_at_minute,
    wiki_code,

    count(*)                                          as edit_count,
    count(distinct editor_name)                       as editor_count,
    sum(case when is_bot then 1 else 0 end)           as bot_edit_count,
    sum(case when not is_bot then 1 else 0 end)       as human_edit_count,

    sum(bytes_changed)                                as net_bytes_changed,
    sum(case when bytes_changed > 0 then bytes_changed else 0 end) as bytes_added,
    sum(case when bytes_changed < 0 then -bytes_changed else 0 end) as bytes_removed,

    round(avg(ingestion_lag_seconds), 1)              as avg_ingestion_lag_seconds,
    max(ingestion_lag_seconds)                        as max_ingestion_lag_seconds

from edits
group by edited_at_minute, wiki_code
