select * from {{ ref('int_tpcds__store_sales_lines') }}
union all
select * from {{ ref('int_tpcds__catalog_sales_lines') }}
union all
select * from {{ ref('int_tpcds__web_sales_lines') }}
