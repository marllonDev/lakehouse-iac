select
    c.nation_name,
    c.region_name,
    year(l.ordered_at)                                  as order_year,
    count(distinct l.order_key)                         as orders,
    sum(l.net_amount)                                   as net_revenue

from {{ ref('fct_tpch_order_lines') }} l
inner join {{ ref('dim_customers') }} c on l.customer_key = c.customer_key
group by c.nation_name, c.region_name, year(l.ordered_at)
