select
    r.channel,
    r.order_id,
    r.item_sk,
    r.customer_sk,
    c.calendar_date,
    c.year,
    c.month,
    r.return_quantity,
    r.return_amount,
    r.return_tax,
    r.net_loss,
    r.reason_sk

from {{ ref('int_tpcds__returns_all_channels') }} r
join {{ ref('int_tpcds__calendar') }} c on r.returned_date_sk = c.date_sk
