{{
    config(
        materialized='streaming_table',
        schema='staging'
    )
}}

{#
  The entry point for the streaming half of the project.

  read_files() with a STREAM prefix is Auto Loader: it keeps track of which
  files in the volume it has already consumed, so each refresh reads only what
  landed since the last one. Re-running is cheap and never double-counts, which
  is what makes this safe to trigger every minute.

  Types are asserted here rather than inferred, so a change in the upstream
  JSON cannot silently reshape the table.
#}

select
    cast(id as bigint)                            as event_id,
    meta.dt                                       as event_at,
    cast(timestamp as timestamp)                  as edited_at,

    wiki                                          as wiki_code,
    server_name                                   as wiki_domain,
    type                                          as change_type,
    cast(namespace as int)                        as namespace_id,

    title                                         as page_title,
    user                                          as editor_name,
    cast(bot as boolean)                          as is_bot,
    cast(minor as boolean)                        as is_minor,

    cast(length.old as int)                       as length_before,
    cast(length.new as int)                       as length_after,
    cast(length.new as int) - cast(length.old as int) as bytes_changed,

    comment                                       as edit_comment,

    _metadata.file_name                           as source_file,
    current_timestamp()                           as ingested_at

from stream read_files(
    '{{ var("wikipedia_landing_path") }}',
    format => 'json',
    schemaEvolutionMode => 'addNewColumns'
)
