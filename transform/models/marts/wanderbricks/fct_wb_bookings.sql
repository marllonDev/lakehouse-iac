{{ config(materialized='incremental', unique_key='booking_id', incremental_strategy='merge') }}

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
