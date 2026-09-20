select
    store_sk, store_id, store_name, number_employees, floor_space,
    division_name, company_name, market_desc, city, county, state, country

from {{ ref('stg_tpcds__store') }}
