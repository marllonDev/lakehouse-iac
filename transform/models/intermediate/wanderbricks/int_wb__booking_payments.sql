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
