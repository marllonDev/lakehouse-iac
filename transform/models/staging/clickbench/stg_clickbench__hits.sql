with source as (

    select * from {{ source('clickbench', 'hits') }}

),

renamed as (

    select
        WatchID as watch_id,
        EventTime as event_at,
        EventDate as event_date,
        CounterID as counter_id,
        ClientIP as client_ip,
        RegionID as region_id,
        UserID as user_id,
        OS as os_id,
        UserAgent as user_agent_id,
        URL as url,
        Referer as referer,
        IsRefresh as is_refresh,
        ResolutionWidth as resolution_width,
        IsMobile as is_mobile,
        MobilePhoneModel as mobile_phone_model,
        SearchEngineID as search_engine_id,
        SearchPhrase as search_phrase,
        AdvEngineID as adv_engine_id,
        IsLink as is_link,
        IsDownload as is_download,
        IsNotBounce as is_not_bounce,
        TraficSourceID as traffic_source_id

    from source

)

select * from renamed
