"""Wanderbricks models: a short-term rental marketplace.

The data is closer to real data than TPC-DS: several tables repeat their id, so
the facts deduplicate on it (keeping the latest row) before anything merges on
that key, and relationships are checked as warnings.
"""

from lib import Model, accepted_values, at_least, merge, not_null, relationship, warn, write_group

SEVERITY = "warn"


def intermediate():
    return [
        Model(
            "int_wb__bookings_enriched",
            """
select
    b.booking_id, b.user_id, b.property_id, b.check_in, b.check_out, b.guests_count,
    b.total_amount, b.status, b.created_at, b.updated_at,
    datediff(b.check_out, b.check_in)        as nights,
    p.host_id,
    p.destination_id,
    p.property_type,
    p.base_price,
    p.bedrooms,
    d.destination,
    d.country                                as destination_country,
    d.state_or_province,
    u.country                                as user_country,
    u.user_type

from {{ ref('stg_wanderbricks__bookings') }} b
left join {{ ref('stg_wanderbricks__properties') }} p   on b.property_id = p.property_id
left join {{ ref('stg_wanderbricks__destinations') }} d on p.destination_id = d.destination_id
left join {{ ref('stg_wanderbricks__users') }} u        on b.user_id = u.user_id
""",
            "A booking with its property, destination and guest attached, and the length of the stay.",
        ),
        Model(
            "int_wb__booking_payments",
            """
select
    booking_id,
    count(*)                                                          as payment_count,
    sum(case when status = 'completed' then amount else 0 end)        as paid_amount,
    sum(case when status = 'refunded'  then amount else 0 end)        as refunded_amount,
    sum(case when status = 'failed'    then 1 else 0 end)             as failed_attempts,
    min(payment_date)                                                  as first_payment_at,
    max(payment_date)                                                  as last_payment_at

from {{ ref('stg_wanderbricks__payments') }}
group by booking_id
""",
            "What was paid, refunded and attempted for each booking.",
        ),
        Model(
            "int_wb__property_reviews",
            """
select
    property_id,
    count(*)                    as review_count,
    avg(rating)                 as avg_rating,
    min(rating)                 as min_rating,
    max(rating)                 as max_rating,
    max(created_at)             as last_review_at

from {{ ref('stg_wanderbricks__reviews') }}
where not coalesce(is_deleted, false)
group by property_id
""",
            "Review counts and ratings per property, ignoring deleted reviews.",
        ),
        Model(
            "int_wb__property_catalog",
            """
with amenities as (

    select property_id, count(*) as amenity_count
    from {{ ref('stg_wanderbricks__property_amenities') }}
    group by property_id

)

select
    p.property_id, p.host_id, p.destination_id, p.title, p.property_type, p.base_price,
    p.max_guests, p.bedrooms, p.bathrooms, p.property_latitude, p.property_longitude, p.created_at,
    h.name                          as host_name,
    h.is_verified                   as host_verified,
    h.rating                        as host_rating,
    d.destination,
    d.country                       as destination_country,
    coalesce(a.amenity_count, 0)    as amenity_count

from {{ ref('stg_wanderbricks__properties') }} p
left join {{ ref('stg_wanderbricks__hosts') }} h         on p.host_id = h.host_id
left join {{ ref('stg_wanderbricks__destinations') }} d  on p.destination_id = d.destination_id
left join amenities a                                    on p.property_id = a.property_id
""",
            "A property with its host, destination and how many amenities it offers.",
        ),
        Model(
            "int_wb__user_events",
            """
select 'page_view' as event_type, user_id, property_id, `timestamp` as event_at,
       device_type as device, page_url as detail
from {{ ref('stg_wanderbricks__page_views') }}

union all

select event, user_id, property_id, `timestamp`, metadata.device, metadata.referrer
from {{ ref('stg_wanderbricks__clickstream') }}
""",
            "Every page view and click in one event stream, with the device it came from.",
        ),
        Model(
            "int_wb__sessions",
            """
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
""",
            "Events grouped into sessions: a gap of more than thirty minutes starts a new one.",
        ),
        Model(
            "int_wb__support_messages",
            """
select
    l.ticket_id,
    l.user_id,
    l.support_agent_id,
    cast(l.created_at as timestamp)              as ticket_created_at,
    m.sender,
    m.sentiment,
    m.message,
    cast(m.`timestamp` as timestamp)             as message_at

from {{ ref('stg_wanderbricks__customer_support_logs') }} l
lateral view explode(l.messages) exploded as m
""",
            "One row per message of a support ticket, unnested from the array it is stored in.",
        ),
        Model(
            "int_wb__host_portfolio",
            """
select
    h.host_id,
    h.name,
    h.is_verified,
    h.is_active,
    h.rating,
    h.country,
    h.joined_at,
    count(p.property_id)          as properties,
    avg(p.base_price)             as avg_base_price,
    sum(p.bedrooms)               as total_bedrooms

from {{ ref('stg_wanderbricks__hosts') }} h
left join {{ ref('stg_wanderbricks__properties') }} p on h.host_id = p.host_id
group by h.host_id, h.name, h.is_verified, h.is_active, h.rating, h.country, h.joined_at
""",
            "A host with how many properties they list and at what price.",
        ),
    ]


def marts():
    dims = [
        Model(
            "dim_wb_property",
            "select * from {{ ref('int_wb__property_catalog') }}",
            "One row per rental property.",
            grain=("property_id",),
            tests=merge(not_null("property_id"), {"base_price": [warn(at_least(0))]}),
        ),
        Model(
            "dim_wb_host",
            "select * from {{ ref('int_wb__host_portfolio') }}",
            "One row per host.",
            grain=("host_id",),
            tests=not_null("host_id"),
        ),
        Model(
            "dim_wb_user",
            """
select
    user_id, name, country, user_type, created_at, is_business,
    datediff(current_date(), cast(created_at as date))       as tenure_days

from {{ ref('stg_wanderbricks__users') }}
""",
            "One row per user, with how long they have had an account.",
            grain=("user_id",),
            tests=merge(not_null("user_id"), {"user_type": [accepted_values("'individual'", "'business'")]}),
        ),
        Model(
            "dim_wb_destination",
            """
select
    d.destination_id, d.destination, d.country, d.state_or_province,
    count(p.property_id)      as properties

from {{ ref('stg_wanderbricks__destinations') }} d
left join {{ ref('stg_wanderbricks__properties') }} p on d.destination_id = p.destination_id
group by d.destination_id, d.destination, d.country, d.state_or_province
""",
            "One row per destination, with how many properties it holds.",
            grain=("destination_id",),
            tests=not_null("destination_id"),
        ),
    ]

    facts = [
        Model(
            "fct_wb_bookings",
            """
select
    e.*,
    p.payment_count,
    p.paid_amount,
    p.refunded_amount,
    p.failed_attempts

from {{ ref('int_wb__bookings_enriched') }} e
left join {{ ref('int_wb__booking_payments') }} p on e.booking_id = p.booking_id

{% if is_incremental() %}
where e.updated_at >= (
    select coalesce(max(updated_at), timestamp'1970-01-01') - interval 1 day from {{ this }}
)
{% endif %}
""",
            "One row per booking. Incremental: a run merges the bookings updated since the day before the newest one it already holds.",
            config="materialized='incremental', unique_key='booking_id', incremental_strategy='merge'",
            grain=("booking_id",),
            tests=merge(
                not_null("booking_id", "property_id"),
                {
                    "status": [accepted_values("'pending'", "'confirmed'", "'cancelled'", "'completed'")],
                    "property_id": [relationship("dim_wb_property", "property_id", SEVERITY)],
                    "user_id": [relationship("dim_wb_user", "user_id", SEVERITY)],
                    "nights": [warn(at_least(0))],
                },
            ),
        ),
        Model(
            "fct_wb_payments",
            """
select
    payment_id, booking_id, amount, payment_method, status, payment_date

from {{ ref('stg_wanderbricks__payments') }}

{% if is_incremental() %}
where payment_date >= (
    select coalesce(max(payment_date), timestamp'1970-01-01') - interval 1 day from {{ this }}
)
{% endif %}

qualify row_number() over (partition by payment_id order by payment_date desc) = 1
""",
            "One row per payment. The source repeats some payment ids, so the latest row of each id is kept, which is what lets it merge on that key.",
            config="materialized='incremental', unique_key='payment_id', incremental_strategy='merge'",
            grain=("payment_id",),
            tests=merge(
                not_null("payment_id", "booking_id"),
                {
                    "status": [accepted_values("'completed'", "'refunded'", "'failed'")],
                    "payment_method": [accepted_values("'paypal'", "'credit_card'", "'apple_pay'", "'bank_transfer'", "'google_pay'")],
                    "amount": [warn(at_least(0))],  # refunds are negative by design; a few completed or failed rows are too
                },
            ),
        ),
        Model(
            "fct_wb_page_views",
            """
select
    view_id, user_id, property_id, `timestamp` as viewed_at, device_type, page_url, referrer

from {{ ref('stg_wanderbricks__page_views') }}
qualify row_number() over (partition by view_id order by `timestamp` desc) = 1
""",
            "One row per page view, deduplicated on the view id.",
            grain=("view_id",),
            tests=merge(
                not_null("view_id", "viewed_at"),
                {"device_type": [accepted_values("'tablet'", "'mobile'", "'desktop'")]},
            ),
        ),
        Model(
            "fct_wb_reviews",
            """
select
    review_id, booking_id, property_id, user_id, rating, comment, created_at

from {{ ref('stg_wanderbricks__reviews') }}
where not coalesce(is_deleted, false)
qualify row_number() over (partition by review_id order by updated_at desc) = 1
""",
            "One row per review that was not deleted, deduplicated on the review id.",
            grain=("review_id",),
            tests=merge(not_null("review_id", "property_id"), {"rating": [("dbt_utils.accepted_range", {"min_value": 0, "max_value": 5, "inclusive": "true"})]}),
        ),
        Model(
            "fct_wb_support_messages",
            "select * from {{ ref('int_wb__support_messages') }}",
            "One row per support message.",
            tests=not_null("ticket_id", "sender"),
        ),
    ]

    aggs = [
        Model(
            "agg_wb_occupancy_by_destination_month",
            """
select
    date_trunc('month', check_in)                                                       as stay_month,
    destination_id,
    destination,
    count(*)                                                                            as bookings,
    sum(case when status <> 'cancelled' then nights else 0 end)                         as nights_booked,
    sum(case when status <> 'cancelled' then total_amount else 0 end)                   as revenue,
    sum(case when status = 'cancelled' then 1 else 0 end)                               as cancellations

from {{ ref('fct_wb_bookings') }}
where destination_id is not null
group by date_trunc('month', check_in), destination_id, destination
""",
            "Bookings, nights, revenue and cancellations by stay month and destination.",
            grain=("stay_month", "destination_id"),
            tests=not_null("stay_month", "destination_id"),
        ),
        Model(
            "agg_wb_revenue_by_host",
            """
select
    b.host_id,
    count(*)                                                                            as bookings,
    sum(case when b.status <> 'cancelled' then b.total_amount else 0 end)               as revenue,
    avg(case when b.status <> 'cancelled' then b.total_amount end)                      as avg_booking_value,
    count(distinct b.property_id)                                                       as properties_booked

from {{ ref('fct_wb_bookings') }} b
where b.host_id is not null
group by b.host_id
""",
            "Revenue and bookings per host.",
            grain=("host_id",),
            tests=not_null("host_id"),
        ),
        Model(
            "agg_wb_rating_by_property_type",
            """
select
    p.property_type,
    count(*)                                  as reviews,
    avg(r.rating)                             as avg_rating,
    percentile_approx(r.rating, 0.5)          as median_rating,
    stddev(r.rating)                          as rating_stddev

from {{ ref('fct_wb_reviews') }} r
join {{ ref('dim_wb_property') }} p on r.property_id = p.property_id
group by p.property_type
""",
            "How guests rate each kind of property.",
            grain=("property_type",),
            tests=not_null("property_type"),
        ),
        Model(
            "agg_wb_conversion_funnel",
            """
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
    {{ safe_divide('coalesce(booked.bookings, 0)', 'views.viewers') }}                     as bookings_per_viewer

from views
left join booked on views.property_id = booked.property_id
""",
            "For each property, how many people looked and how many booked.",
            grain=("property_id",),
            tests=not_null("property_id"),
        ),
        Model(
            "agg_wb_session_metrics",
            """
select
    cast(session_start as date)                                                     as session_date,
    count(*)                                                                        as sessions,
    avg(events)                                                                     as avg_events,
    avg(unix_timestamp(session_end) - unix_timestamp(session_start))                as avg_duration_seconds,
    sum(searches)                                                                   as searches

from {{ ref('int_wb__sessions') }}
group by cast(session_start as date)
""",
            "Sessions per day, and how long and busy they were.",
            grain=("session_date",),
            tests=not_null("session_date"),
        ),
        Model(
            "agg_wb_cancellation_rate_by_month",
            """
select
    date_trunc('month', created_at)                                                 as booking_month,
    count(*)                                                                        as bookings,
    sum(case when status = 'cancelled' then 1 else 0 end)                           as cancelled,
    sum(case when status = 'cancelled' then 1 else 0 end) / count(*)                as cancellation_rate

from {{ ref('fct_wb_bookings') }}
group by date_trunc('month', created_at)
""",
            "The share of bookings that were cancelled, by the month they were made.",
            grain=("booking_month",),
            tests=merge(not_null("booking_month"), {"cancellation_rate": [("dbt_utils.accepted_range", {"min_value": 0, "max_value": 1, "inclusive": "true"})]}),
        ),
        Model(
            "agg_wb_payment_method_mix",
            """
select
    p.payment_method,
    p.status,
    m.is_instant,
    count(*)                    as payments,
    sum(p.amount)               as amount,
    sum(p.amount) * m.fee_rate  as estimated_fees

from {{ ref('fct_wb_payments') }} p
left join {{ ref('seed_wb_payment_methods') }} m on p.payment_method = m.payment_method
group by p.payment_method, p.status, m.is_instant, m.fee_rate
""",
            "Payments and money by method and outcome, with the fees the method would charge.",
            grain=("payment_method", "status"),
            tests=not_null("payment_method", "status"),
        ),
        Model(
            "agg_wb_user_ltv",
            """
select
    user_id,
    count(*)                                                                            as bookings,
    sum(case when status <> 'cancelled' then total_amount else 0 end)                   as total_spend,
    min(created_at)                                                                     as first_booking_at,
    max(created_at)                                                                     as last_booking_at,
    ntile(10) over (order by sum(case when status <> 'cancelled' then total_amount else 0 end)) as spend_decile

from {{ ref('fct_wb_bookings') }}
where user_id is not null
group by user_id
""",
            "Lifetime spend per user, with the decile of spend they fall in.",
            grain=("user_id",),
            tests=merge(not_null("user_id"), {"spend_decile": [("dbt_utils.accepted_range", {"min_value": 1, "max_value": 10, "inclusive": "true"})]}),
        ),
        Model(
            "agg_wb_seasonality",
            """
select
    month(check_in)                                         as check_in_month,
    property_type,
    count(*)                                                as bookings,
    avg(total_amount / nullif(nights, 0))                   as avg_price_per_night

from {{ ref('fct_wb_bookings') }}
where property_type is not null
group by month(check_in), property_type
""",
            "Which months each kind of property gets booked in, and at what nightly price.",
            grain=("check_in_month", "property_type"),
            tests=not_null("check_in_month", "property_type"),
        ),
        Model(
            "agg_wb_top_properties",
            """
with revenue as (

    select
        destination_id,
        property_id,
        sum(case when status <> 'cancelled' then total_amount else 0 end)               as revenue
    from {{ ref('fct_wb_bookings') }}
    where destination_id is not null
    group by destination_id, property_id

),

ranked as (

    select *, row_number() over (partition by destination_id order by revenue desc) as revenue_rank
    from revenue

)

select * from ranked where revenue_rank <= 10
""",
            "The ten properties that earned the most in each destination.",
            grain=("destination_id", "property_id"),
            tests=not_null("destination_id", "property_id"),
        ),
        Model(
            "agg_wb_support_sentiment",
            """
select
    sender,
    sentiment,
    count(*)                                                                        as messages,
    count(distinct ticket_id)                                                       as tickets,
    count(*) / sum(count(*)) over (partition by sender)                             as share_of_sender

from {{ ref('fct_wb_support_messages') }}
where sentiment is not null
group by sender, sentiment
""",
            "The tone of support messages, by who sent them.",
            grain=("sender", "sentiment"),
            tests=not_null("sender", "sentiment"),
        ),
    ]
    return dims + facts + aggs


def generate():
    n = write_group("intermediate/wanderbricks", "_int_wanderbricks__models.yml", intermediate())
    n += write_group("marts/wanderbricks", "_wanderbricks__models.yml", marts())
    return n
