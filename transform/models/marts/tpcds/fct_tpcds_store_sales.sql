select
    s.order_id                        as ticket_number,
    s.item_sk,
    s.customer_sk,
    s.store_sk,
    s.promo_sk,
    c.calendar_date,
    c.year,
    c.month,
    s.quantity,
    s.ext_sales_price,
    s.net_paid,
    s.net_profit

from {{ ref('int_tpcds__store_sales_lines') }} s
join {{ ref('int_tpcds__calendar') }} c on s.sold_date_sk = c.date_sk
