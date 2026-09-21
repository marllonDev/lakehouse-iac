select
    p.brand,
    p.manufacturer,
    count(*)                                            as lines,
    sum(l.quantity)                                     as units_sold,
    sum(l.net_amount)                                   as net_revenue,
    avg(l.discount_rate)                                as avg_discount

from {{ ref('fct_tpch_order_lines') }} l
inner join {{ ref('dim_tpch_part') }} p on l.part_key = p.part_key
group by p.brand, p.manufacturer
