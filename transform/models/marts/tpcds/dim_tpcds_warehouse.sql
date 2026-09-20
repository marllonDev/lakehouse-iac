select warehouse_sk, warehouse_name, warehouse_sq_ft, city, state, country
from {{ ref('stg_tpcds__warehouse') }}
