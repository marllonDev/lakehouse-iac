-- The sales fact joins the calendar; a line whose date is missing would vanish.
select lines.n as line_rows, fact.n as fact_rows
from (select count(*) as n from {{ ref('int_tpcds__sales_all_channels') }}) lines
cross join (select count(*) as n from {{ ref('fct_tpcds_sales') }}) fact
where lines.n <> fact.n
