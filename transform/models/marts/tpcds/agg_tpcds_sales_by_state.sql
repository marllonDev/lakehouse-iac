select
    c.state,
    s.year,
    sum(s.ext_sales_price)            as revenue,
    count(distinct s.customer_sk)     as customers,
    count(distinct s.order_id)        as orders

from {{ ref('fct_tpcds_sales') }} s
join {{ ref('dim_tpcds_customer') }} c on s.customer_sk = c.customer_sk
where c.state is not null
group by c.state, s.year
