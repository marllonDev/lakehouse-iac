select
    s.supplier_key, s.supplier_name, s.nation_name, s.region_name,
    p.lines_supplied, p.units_supplied, p.net_revenue, p.avg_days_to_ship, p.late_share,
    rank() over (partition by s.region_name order by p.net_revenue desc)    as revenue_rank_in_region

from {{ ref('dim_tpch_supplier') }} s
inner join {{ ref('int_tpch__supplier_performance') }} p on s.supplier_key = p.supplier_key
