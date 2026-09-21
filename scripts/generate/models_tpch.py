"""TPC-H models beyond the original three marts.

The original marts (fct_orders, dim_customers, agg_sales_by_month) live in
models/marts. These add the supplier and part side of the schema and the line
level, which is where the 30 million rows are.
"""

from lib import Model, accepted_values, at_least, between, merge, not_null, relationship, write_group


def intermediate():
    return [
        Model(
            "int_tpch__order_lines_enriched",
            """
select
    l.order_line_key, l.order_key, l.line_number, l.part_key, l.supplier_key,
    l.quantity, l.gross_amount, l.discount_rate, l.net_amount, l.net_amount_with_tax,
    l.shipped_at, l.committed_at, l.received_at, l.ship_mode, l.return_flag,
    o.customer_key,
    o.ordered_at,
    o.order_status,
    o.order_priority,
    datediff(l.shipped_at, o.ordered_at)        as days_to_ship,
    datediff(l.received_at, l.committed_at)     as days_late,
    l.received_at > l.committed_at              as is_late

from {{ ref('stg_order_lines') }} l
inner join {{ ref('stg_orders') }} o on l.order_key = o.order_key
""",
            "A line item with the order it belongs to, and how long it took to ship and arrive.",
        ),
        Model(
            "int_tpch__supplier_parts",
            """
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
""",
            "Which supplier offers which part, at what cost, with the part and the supplier's place attached.",
        ),
        Model(
            "int_tpch__customer_orders",
            """
select
    customer_key,
    count(*)                                        as orders,
    sum(order_total)                                as total_ordered,
    min(ordered_at)                                 as first_ordered_at,
    max(ordered_at)                                 as last_ordered_at,
    sum(case when order_status = 'open' then 1 else 0 end) as open_orders

from {{ ref('stg_orders') }}
group by customer_key
""",
            "How much and how often each customer has ordered.",
        ),
        Model(
            "int_tpch__supplier_performance",
            """
select
    supplier_key,
    count(*)                                        as lines_supplied,
    sum(quantity)                                   as units_supplied,
    sum(net_amount)                                 as net_revenue,
    avg(days_to_ship)                               as avg_days_to_ship,
    avg(case when is_late then 1.0 else 0.0 end)    as late_share

from {{ ref('int_tpch__order_lines_enriched') }}
group by supplier_key
""",
            "How much each supplier shipped and how often it arrived late.",
        ),
        Model(
            "int_tpch__part_demand",
            """
select
    part_key,
    date_trunc('year', ordered_at)                  as demand_year,
    sum(quantity)                                   as units_sold,
    sum(net_amount)                                 as net_revenue,
    count(distinct customer_key)                    as customers

from {{ ref('int_tpch__order_lines_enriched') }}
group by part_key, date_trunc('year', ordered_at)
""",
            "Units, revenue and buyers of each part in each year.",
        ),
    ]


def marts():
    dims = [
        Model(
            "dim_tpch_supplier",
            """
select
    s.supplier_key, s.supplier_name, s.address, s.phone_number, s.account_balance,
    n.nation_name,
    r.region_name

from {{ ref('stg_suppliers') }} s
left join {{ ref('stg_nations') }} n on s.nation_key = n.nation_key
left join {{ ref('stg_regions') }} r on n.region_key = r.region_key
""",
            "One row per supplier with the nation and region it sits in.",
            grain=("supplier_key",),
            tests=not_null("supplier_key", "supplier_name"),
        ),
        Model(
            "dim_tpch_part",
            "select * from {{ ref('stg_parts') }}",
            "One row per part.",
            grain=("part_key",),
            tests=merge(not_null("part_key"), {"retail_price": [at_least(0)], "part_size": [at_least(1)]}),
        ),
        Model(
            "dim_tpch_customer_value",
            """
select
    c.customer_key, c.customer_name, c.market_segment, c.nation_name, c.region_name,
    coalesce(o.orders, 0)               as orders,
    coalesce(o.total_ordered, 0)        as total_ordered,
    o.first_ordered_at,
    o.last_ordered_at

from {{ ref('dim_customers') }} c
left join {{ ref('int_tpch__customer_orders') }} o on c.customer_key = o.customer_key
""",
            "One row per customer with what they have ordered so far.",
            grain=("customer_key",),
            tests=not_null("customer_key"),
        ),
    ]

    facts = [
        Model(
            "fct_tpch_order_lines",
            "select * from {{ ref('int_tpch__order_lines_enriched') }}",
            "One row per order line: the largest table in the project, about thirty million rows.",
            grain=("order_line_key",),
            tests=merge(
                not_null("order_line_key", "order_key", "part_key", "supplier_key"),
                {
                    "return_flag": [accepted_values("'R'", "'A'", "'N'")],
                    "ship_mode": [accepted_values("'AIR'", "'FOB'", "'MAIL'", "'RAIL'", "'REG AIR'", "'SHIP'", "'TRUCK'")],
                    "discount_rate": [between(0, 0.1)],
                    "quantity": [between(1, 50)],
                },
            ),
        ),
        Model(
            "fct_tpch_supplier_parts",
            "select * from {{ ref('int_tpch__supplier_parts') }}",
            "One row per part a supplier offers.",
            grain=("part_key", "supplier_key"),
            tests=merge(not_null("part_key", "supplier_key"), {"supply_cost": [at_least(0)]}),
        ),
    ]

    aggs = [
        Model(
            "agg_tpch_pricing_summary",
            """
select
    return_flag,
    order_status,
    sum(quantity)                                       as sum_quantity,
    sum(gross_amount)                                   as sum_base_price,
    sum(net_amount)                                     as sum_disc_price,
    sum(net_amount_with_tax)                            as sum_charge,
    avg(quantity)                                       as avg_quantity,
    avg(discount_rate)                                  as avg_discount,
    count(*)                                            as line_count

from {{ ref('fct_tpch_order_lines') }}
group by return_flag, order_status
""",
            "Quantities and prices of every line, by return flag and order status (TPC-H's pricing summary).",
            grain=("return_flag", "order_status"),
            tests=not_null("return_flag", "order_status"),
        ),
        Model(
            "agg_tpch_shipping_modes",
            """
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
""",
            "How fast and how reliably each shipping mode delivers, against the days it promises.",
            grain=("ship_mode",),
            tests=merge(not_null("ship_mode"), {"late_share": [between(0, 1)]}),
        ),
        Model(
            "agg_tpch_supplier_revenue",
            """
select
    s.supplier_key, s.supplier_name, s.nation_name, s.region_name,
    p.lines_supplied, p.units_supplied, p.net_revenue, p.avg_days_to_ship, p.late_share,
    rank() over (partition by s.region_name order by p.net_revenue desc)    as revenue_rank_in_region

from {{ ref('dim_tpch_supplier') }} s
inner join {{ ref('int_tpch__supplier_performance') }} p on s.supplier_key = p.supplier_key
""",
            "Revenue and delivery record of each supplier, ranked inside its region.",
            grain=("supplier_key",),
            tests=not_null("supplier_key"),
        ),
        Model(
            "agg_tpch_revenue_by_nation_year",
            """
select
    c.nation_name,
    c.region_name,
    year(l.ordered_at)                                  as order_year,
    count(distinct l.order_key)                         as orders,
    sum(l.net_amount)                                   as net_revenue

from {{ ref('fct_tpch_order_lines') }} l
inner join {{ ref('dim_customers') }} c on l.customer_key = c.customer_key
group by c.nation_name, c.region_name, year(l.ordered_at)
""",
            "Revenue by the customer's nation and the year of the order.",
            grain=("nation_name", "order_year"),
            tests=not_null("nation_name", "order_year"),
        ),
        Model(
            "agg_tpch_brand_performance",
            """
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
""",
            "Sales of each brand.",
            grain=("brand", "manufacturer"),
            tests=not_null("brand", "manufacturer"),
        ),
        Model(
            "agg_tpch_part_type_margin",
            """
select
    part_type,
    count(*)                                            as offers,
    avg(supply_cost)                                    as avg_supply_cost,
    avg(retail_price)                                   as avg_retail_price,
    avg(margin_per_unit)                                as avg_margin_per_unit

from {{ ref('fct_tpch_supplier_parts') }}
group by part_type
""",
            "The margin between supply cost and retail price, by kind of part.",
            grain=("part_type",),
            tests=not_null("part_type"),
        ),
        Model(
            "agg_tpch_customer_segments",
            """
select
    market_segment,
    count(*)                                            as customers,
    sum(orders)                                         as orders,
    sum(total_ordered)                                  as total_ordered,
    avg(total_ordered)                                  as avg_customer_value

from {{ ref('dim_tpch_customer_value') }}
group by market_segment
""",
            "Customers and their spend by market segment.",
            grain=("market_segment",),
            tests=not_null("market_segment"),
        ),
        Model(
            "agg_tpch_late_deliveries",
            """
select
    date_trunc('month', shipped_at)                     as ship_month,
    count(*)                                            as lines,
    sum(case when is_late then 1 else 0 end)            as late_lines,
    avg(days_late)                                      as avg_days_late

from {{ ref('fct_tpch_order_lines') }}
group by date_trunc('month', shipped_at)
""",
            "How many lines arrived after the committed date, by shipping month.",
            grain=("ship_month",),
            tests=not_null("ship_month"),
        ),
        Model(
            "agg_tpch_priority_service",
            """
select
    f.order_priority,
    w.priority_weight,
    count(distinct f.order_key)                         as orders,
    count(distinct f.order_key) * w.priority_weight     as weighted_orders,
    avg(f.days_to_ship)                                 as avg_days_to_ship,
    avg(case when f.is_late then 1.0 else 0.0 end)      as late_share

from {{ ref('fct_tpch_order_lines') }} f
left join {{ ref('seed_tpch_priority_weights') }} w on f.order_priority = w.order_priority
group by f.order_priority, w.priority_weight
""",
            "Whether higher-priority orders ship faster, and how many orders count once weighted by urgency.",
            grain=("order_priority",),
            tests=not_null("order_priority"),
        ),
        Model(
            "agg_tpch_top_parts_by_year",
            """
with ranked as (

    select
        d.part_key,
        d.demand_year,
        d.units_sold,
        d.net_revenue,
        row_number() over (partition by d.demand_year order by d.net_revenue desc) as revenue_rank

    from {{ ref('int_tpch__part_demand') }} d

)

select r.*, p.part_name, p.brand
from ranked r
inner join {{ ref('dim_tpch_part') }} p on r.part_key = p.part_key
where r.revenue_rank <= 25
""",
            "The twenty-five parts that earned the most each year.",
            grain=("demand_year", "part_key"),
            tests=not_null("part_key", "demand_year"),
        ),
    ]
    return dims + facts + aggs


def generate():
    n = write_group("intermediate/tpch", "_int_tpch__models.yml", intermediate())
    n += write_group("marts/tpch", "_tpch__models.yml", marts())
    return n
