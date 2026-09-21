with purchases as (

    select distinct customer_sk, year * 12 + month as month_index
    from {{ ref('fct_tpcds_sales') }}
    where customer_sk is not null

),

cohorts as (

    select customer_sk, min(month_index) as cohort_index
    from purchases
    group by customer_sk

)

select
    cohorts.cohort_index,
    purchases.month_index - cohorts.cohort_index                                  as months_since_first,
    count(distinct purchases.customer_sk)                                          as active_customers,
    max(count(distinct purchases.customer_sk)) over (partition by cohorts.cohort_index) as cohort_peak

from purchases
join cohorts on purchases.customer_sk = cohorts.customer_sk
group by cohorts.cohort_index, purchases.month_index - cohorts.cohort_index
