-- The all-channels view is a union, so its row count is the sum of the three channels.
with channels as (
    select
        (select count(*) from {{ ref('int_tpcds__store_sales_lines') }})
      + (select count(*) from {{ ref('int_tpcds__catalog_sales_lines') }})
      + (select count(*) from {{ ref('int_tpcds__web_sales_lines') }}) as expected_rows
),

combined as (
    select count(*) as actual_rows from {{ ref('int_tpcds__sales_all_channels') }}
)

select * from channels cross join combined
where expected_rows <> actual_rows
