with views as (

    select property_id, count(*) as page_views, count(distinct user_id) as viewers
    from {{ ref('fct_wb_page_views') }}
    group by property_id

),

booked as (

    select property_id, count(*) as bookings
    from {{ ref('fct_wb_bookings') }}
    group by property_id

)

select
    views.property_id,
    views.page_views,
    views.viewers,
    coalesce(booked.bookings, 0)                                                as bookings,
    coalesce(booked.bookings, 0) / nullif(views.viewers, 0)                     as bookings_per_viewer

from views
left join booked on views.property_id = booked.property_id
