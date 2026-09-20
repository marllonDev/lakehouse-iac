select
    st.store_sk,
    st.store_name,
    st.state,
    s.year,
    sum(s.ext_sales_price)                                                              as revenue,
    sum(s.net_profit)                                                                   as profit,
    sum(s.ext_sales_price) / nullif(max(st.floor_space), 0)                             as revenue_per_sq_ft

from {{ ref('fct_tpcds_store_sales') }} s
join {{ ref('dim_tpcds_store') }} st on s.store_sk = st.store_sk
group by st.store_sk, st.store_name, st.state, s.year
