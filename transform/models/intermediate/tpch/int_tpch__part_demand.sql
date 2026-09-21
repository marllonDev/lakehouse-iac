select
    part_key,
    date_trunc('year', ordered_at)                  as demand_year,
    sum(quantity)                                   as units_sold,
    sum(net_amount)                                 as net_revenue,
    count(distinct customer_key)                    as customers

from {{ ref('int_tpch__order_lines_enriched') }}
group by part_key, date_trunc('year', ordered_at)
