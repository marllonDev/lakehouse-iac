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
