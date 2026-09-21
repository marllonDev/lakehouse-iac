select
    s.supplier_key, s.supplier_name, s.address, s.phone_number, s.account_balance,
    n.nation_name,
    r.region_name

from {{ ref('stg_suppliers') }} s
left join {{ ref('stg_nations') }} n on s.nation_key = n.nation_key
left join {{ ref('stg_regions') }} r on n.region_key = r.region_key
