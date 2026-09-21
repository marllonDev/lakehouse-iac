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
