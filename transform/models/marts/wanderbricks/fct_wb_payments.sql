{{ config(materialized='incremental', unique_key='payment_id', incremental_strategy='merge') }}

select
    payment_id, booking_id, amount, payment_method, status, payment_date

from {{ ref('stg_wanderbricks__payments') }}

{% if is_incremental() %}
where payment_date >= (
    select coalesce(max(payment_date), timestamp'1970-01-01') - interval 1 day from {{ this }}
)
{% endif %}

qualify row_number() over (partition by payment_id order by payment_date desc) = 1
