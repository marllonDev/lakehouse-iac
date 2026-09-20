select
    payment_method,
    status,
    count(*)                    as payments,
    sum(amount)                 as amount

from {{ ref('fct_wb_payments') }}
group by payment_method, status
