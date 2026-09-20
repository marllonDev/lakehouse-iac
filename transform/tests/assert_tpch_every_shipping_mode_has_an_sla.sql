-- A shipping mode missing from the seed would silently drop out of the SLA share.
select distinct f.ship_mode
from {{ ref('fct_tpch_order_lines') }} f
left join {{ ref('seed_ship_mode_sla') }} s on f.ship_mode = s.ship_mode
where s.ship_mode is null
