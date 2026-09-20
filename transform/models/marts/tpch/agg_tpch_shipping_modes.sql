select
    f.ship_mode,
    s.sla_days,
    count(*)                                                        as lines,
    avg(f.days_to_ship)                                             as avg_days_to_ship,
    avg(case when f.is_late then 1.0 else 0.0 end)                  as late_share,
    {{ safe_divide('sum(case when f.days_to_ship <= s.sla_days then 1 else 0 end)', 'count(*)') }} as within_sla_share,
    sum(f.net_amount)                                               as net_revenue

from {{ ref('fct_tpch_order_lines') }} f
left join {{ ref('seed_ship_mode_sla') }} s on f.ship_mode = s.ship_mode
group by f.ship_mode, s.sla_days
