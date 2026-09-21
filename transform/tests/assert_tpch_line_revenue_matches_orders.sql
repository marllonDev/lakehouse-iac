-- fct_orders sums each order's lines and fct_tpch_order_lines lists them, so both
-- must add up to the same net revenue, to within floating point noise.
with by_order as (
    select sum(net_amount) as revenue from {{ ref('fct_orders') }}
),

by_line as (
    select sum(net_amount) as revenue from {{ ref('fct_tpch_order_lines') }}
)

select by_order.revenue as order_revenue, by_line.revenue as line_revenue
from by_order
cross join by_line
where abs(by_order.revenue - by_line.revenue) > 0.0001 * by_line.revenue
