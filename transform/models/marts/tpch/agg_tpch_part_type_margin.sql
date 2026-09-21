select
    part_type,
    count(*)                                            as offers,
    avg(supply_cost)                                    as avg_supply_cost,
    avg(retail_price)                                   as avg_retail_price,
    avg(margin_per_unit)                                as avg_margin_per_unit

from {{ ref('fct_tpch_supplier_parts') }}
group by part_type
