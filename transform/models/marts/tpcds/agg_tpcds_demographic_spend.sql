select
    c.gender,
    c.marital_status,
    c.education_status,
    s.year,
    count(distinct s.customer_sk)                                       as customers,
    sum(s.ext_sales_price)                                              as revenue,
    sum(s.ext_sales_price) / nullif(count(distinct s.order_id), 0)      as avg_order_value

from {{ ref('fct_tpcds_sales') }} s
join {{ ref('dim_tpcds_customer') }} c on s.customer_sk = c.customer_sk
where c.gender is not null
group by c.gender, c.marital_status, c.education_status, s.year
