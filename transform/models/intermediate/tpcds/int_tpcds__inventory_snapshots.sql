select
    inv.date_sk,
    cal.calendar_date,
    cal.year,
    cal.month,
    inv.item_sk,
    it.category,
    inv.warehouse_sk,
    inv.quantity_on_hand

from {{ ref('stg_tpcds__inventory') }} inv
join {{ ref('int_tpcds__calendar') }} cal      on inv.date_sk = cal.date_sk
join {{ ref('int_tpcds__item_hierarchy') }} it on inv.item_sk = it.item_sk
