with customer as (select * from {{ ref('stg_tpcds__customer') }}),
address as (select * from {{ ref('stg_tpcds__customer_address') }}),
demographics as (select * from {{ ref('stg_tpcds__customer_demographics') }}),
household as (select * from {{ ref('stg_tpcds__household_demographics') }}),
bands as (select * from {{ ref('stg_tpcds__income_band') }})

select
    c.customer_sk,
    c.customer_id,
    c.first_name,
    c.last_name,
    c.birth_year,
    c.birth_country,
    c.preferred_cust_flag,
    a.state,
    a.county,
    a.city,
    a.country,
    d.gender,
    d.marital_status,
    d.education_status,
    d.credit_rating,
    d.purchase_estimate,
    h.buy_potential,
    h.vehicle_count,
    h.dep_count       as household_dependents,
    b.lower_bound     as income_lower_bound,
    b.upper_bound     as income_upper_bound

from customer c
left join address a       on c.current_addr_sk = a.address_sk
left join demographics d  on c.current_cdemo_sk = d.demo_sk
left join household h     on c.current_hdemo_sk = h.demo_sk
left join bands b         on h.income_band_sk = b.income_band_sk
