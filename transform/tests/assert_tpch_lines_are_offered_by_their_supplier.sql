{{ config(severity='warn') }}

-- TPC-H guarantees that a line's supplier offers the part, so this should be empty.
select l.order_line_key, l.part_key, l.supplier_key
from {{ ref('fct_tpch_order_lines') }} l
left join {{ ref('fct_tpch_supplier_parts') }} sp
    on l.part_key = sp.part_key and l.supplier_key = sp.supplier_key
where sp.part_key is null
