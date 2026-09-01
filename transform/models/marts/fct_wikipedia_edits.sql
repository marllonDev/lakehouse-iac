{{
    config(
        materialized='incremental',
        unique_key='edit_key',
        incremental_strategy='merge',
        partition_by=['edited_at_date'],
        on_schema_change='append_new_columns'
    )
}}

with edits as (

    select * from {{ ref('st_wikipedia_edits') }}

    {% if is_incremental() %}
        -- The streaming table only ever grows, so a watermark on ingestion time
        -- is enough. A ten-minute overlap absorbs clock skew between the
        -- ingestion task and this run; the merge makes the overlap harmless.
        where ingested_at >= (
            select dateadd(minute, -10, max(ingested_at)) from {{ this }}
        )
    {% endif %}

),

final as (

    select
        -- Wikimedia's event id is only unique within a wiki, so the key has to
        -- carry the wiki as well.
        {{ dbt_utils.generate_surrogate_key(['wiki_code', 'event_id']) }} as edit_key,

        event_id,
        wiki_code,
        wiki_domain,
        change_type,
        namespace_id,
        page_title,
        editor_name,
        is_bot,
        is_minor,
        length_before,
        length_after,
        bytes_changed,

        edited_at,
        cast(edited_at as date)                as edited_at_date,
        date_trunc('minute', edited_at)        as edited_at_minute,
        ingested_at,

        -- Latency of the pipeline itself, measured per row. This is what makes
        -- the "how real-time is it really" question answerable with data
        -- instead of a claim.
        timestampdiff(second, edited_at, ingested_at) as ingestion_lag_seconds

    from edits

)

select * from final
