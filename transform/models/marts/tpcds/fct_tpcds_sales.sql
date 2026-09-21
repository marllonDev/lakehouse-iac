select
    s.channel,
    s.order_id,
    s.item_sk,
    s.customer_sk,
    s.store_sk,
    s.promo_sk,
    s.sold_date_sk,
    c.calendar_date,
    c.year,
    c.month,
    c.quarter,
    c.day_name,
    c.is_weekend,
    s.quantity,
    s.sales_price,
    s.ext_sales_price,
    s.ext_list_price,
    s.coupon_amt,
    s.net_paid,
    s.net_profit,
    s.ext_list_price - s.ext_sales_price                                  as discount_amount

from {{ ref('int_tpcds__sales_all_channels') }} s
join {{ ref('int_tpcds__calendar') }} c on s.sold_date_sk = c.date_sk
