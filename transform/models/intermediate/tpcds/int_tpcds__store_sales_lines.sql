select
    'store'          as channel,
    ticket_number    as order_id,
    store_sk,
    
    item_sk, customer_sk, promo_sk, sold_date_sk,
    quantity, sales_price, ext_sales_price, ext_list_price, coupon_amt, net_paid, net_profit


from {{ ref('stg_tpcds__store_sales') }}
where sold_date_sk is not null
