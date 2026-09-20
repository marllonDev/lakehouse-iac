select
    item_sk,
    item_id,
    product_name,
    category,
    `class`                                as item_class,
    brand,
    manufact,
    current_price,
    wholesale_cost,
    current_price - wholesale_cost         as unit_margin,
    size,
    color,
    units

from {{ ref('stg_tpcds__item') }}
