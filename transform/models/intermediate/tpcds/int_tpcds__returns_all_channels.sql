select 'store' as channel, ticket_number as order_id, item_sk, customer_sk, returned_date_sk,
       return_quantity, return_amt as return_amount, return_tax, net_loss, reason_sk
from {{ ref('stg_tpcds__store_returns') }}

union all

select 'catalog', order_number, item_sk, returning_customer_sk, returned_date_sk,
       return_quantity, return_amount, return_tax, net_loss, reason_sk
from {{ ref('stg_tpcds__catalog_returns') }}

union all

select 'web', order_number, item_sk, returning_customer_sk, returned_date_sk,
       return_quantity, return_amt, return_tax, net_loss, reason_sk
from {{ ref('stg_tpcds__web_returns') }}
