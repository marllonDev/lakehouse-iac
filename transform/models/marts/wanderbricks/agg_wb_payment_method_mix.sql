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
