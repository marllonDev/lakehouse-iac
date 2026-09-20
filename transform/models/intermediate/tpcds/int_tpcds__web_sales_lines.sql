select
    'web'                              as channel,
    order_number                       as order_id,
    cast(null as bigint)               as store_sk,
    item_sk,
    bill_customer_sk                   as customer_sk,
    promo_sk,
    sold_date_sk,
    quantity, sales_price, ext_sales_price, ext_list_price, coupon_amt, net_paid, net_profit

from {{ ref('stg_tpcds__web_sales') }}
where sold_date_sk is not null
