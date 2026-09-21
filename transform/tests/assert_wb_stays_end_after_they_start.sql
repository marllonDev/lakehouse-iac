{{ config(severity='warn') }}

select booking_id, check_in, check_out
from {{ ref('fct_wb_bookings') }}
where check_out < check_in
