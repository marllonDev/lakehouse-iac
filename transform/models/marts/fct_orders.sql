{{
    config(
        materialized='incremental',
        unique_key='order_key',
        incremental_strategy='merge',
        partition_by=['ordered_at_month'],
        on_schema_change='fail'
    )
}}

with orders as (

    select * from {{ ref('stg_orders') }}

    {% if is_incremental() %}
        -- Reprocess a trailing window rather than only strictly-new rows, so
        -- late-arriving lines on a recent order still land. The merge on
        -- order_key makes the overlap idempotent.
        where ordered_at >= (
            select dateadd(day, -3, max(ordered_at)) from {{ this }}
        )
    {% endif %}

),

order_lines as (

    select * from {{ ref('stg_order_lines') }}

),

line_totals as (

    select
        order_key,
        count(*)              as line_count,
        sum(quantity)         as total_quantity,
        sum(gross_amount)     as gross_amount,
        sum(net_amount)       as net_amount,
        sum(net_amount_with_tax) as net_amount_with_tax,
        min(shipped_at)       as first_shipped_at,
        max(received_at)      as last_received_at

    from order_lines
    group by order_key

),

final as (

    select
        orders.order_key,
        orders.customer_key,
        orders.ordered_at,
        date_trunc('month', orders.ordered_at) as ordered_at_month,
        orders.order_status,
        orders.order_priority,
        orders.order_total,

        coalesce(line_totals.line_count, 0)      as line_count,
        line_totals.total_quantity,
        line_totals.gross_amount,
        line_totals.net_amount,
        line_totals.net_amount_with_tax,
        line_totals.first_shipped_at,
        line_totals.last_received_at,

        datediff(line_totals.last_received_at, orders.ordered_at) as days_to_final_receipt

    from orders
    left join line_totals on orders.order_key = line_totals.order_key

)

select * from final
