select
    ps.part_key, ps.supplier_key, ps.available_quantity, ps.supply_cost,
    p.part_name, p.manufacturer, p.brand, p.part_type, p.part_size, p.container, p.retail_price,
    s.supplier_name, s.nation_key, s.account_balance,
    n.nation_name,
    r.region_name,
    p.retail_price - ps.supply_cost             as margin_per_unit

from {{ ref('stg_part_suppliers') }} ps
inner join {{ ref('stg_parts') }} p         on ps.part_key = p.part_key
inner join {{ ref('stg_suppliers') }} s     on ps.supplier_key = s.supplier_key
left join {{ ref('stg_nations') }} n        on s.nation_key = n.nation_key
left join {{ ref('stg_regions') }} r        on n.region_key = r.region_key
