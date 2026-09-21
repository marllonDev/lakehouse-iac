"""TPC-DS models: a retail star schema with three sales channels."""

from lib import Model, at_least, merge, not_null, relationship, accepted_values, write_group

SALES_COLUMNS = """
    item_sk, customer_sk, promo_sk, sold_date_sk,
    quantity, sales_price, ext_sales_price, ext_list_price, coupon_amt, net_paid, net_profit
"""


def intermediate():
    return [
        Model(
            "int_tpcds__calendar",
            """
select
    date_sk,
    `date`                                                              as calendar_date,
    year,
    moy                                                                 as month,
    qoy                                                                 as quarter,
    dom                                                                 as day_of_month,
    day_name,
    week_seq,
    month_seq,
    weekend = 'Y'                                                       as is_weekend,
    holiday = 'Y'                                                       as is_holiday,
    concat(cast(year as string), '-', lpad(cast(moy as string), 2, '0')) as year_month

from {{ ref('stg_tpcds__date_dim') }}
""",
            "The TPC-DS date dimension with readable names and boolean flags.",
        ),
        Model(
            "int_tpcds__item_hierarchy",
            """
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
""",
            "Items with their category, class and brand, and the margin between price and cost.",
        ),
        Model(
            "int_tpcds__customer_profile",
            """
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
""",
            "A customer with the address, demographics, household and income band joined in.",
        ),
        Model(
            "int_tpcds__store_dim",
            """
select
    store_sk, store_id, store_name, number_employees, floor_space,
    division_name, company_name, market_desc, city, county, state, country

from {{ ref('stg_tpcds__store') }}
""",
            "Stores with their geography and size.",
        ),
        Model(
            "int_tpcds__store_sales_lines",
            f"""
select
    'store'          as channel,
    ticket_number    as order_id,
    store_sk,
    {SALES_COLUMNS}

from {{{{ ref('stg_tpcds__store_sales') }}}}
where sold_date_sk is not null
""",
            "Store sales lines in the shape shared by every channel.",
        ),
        Model(
            "int_tpcds__catalog_sales_lines",
            f"""
select
    'catalog'                          as channel,
    order_number                       as order_id,
    cast(null as bigint)               as store_sk,
    item_sk,
    bill_customer_sk                   as customer_sk,
    promo_sk,
    sold_date_sk,
    quantity, sales_price, ext_sales_price, ext_list_price, coupon_amt, net_paid, net_profit

from {{{{ ref('stg_tpcds__catalog_sales') }}}}
where sold_date_sk is not null
""",
            "Catalog sales lines in the shape shared by every channel.",
        ),
        Model(
            "int_tpcds__web_sales_lines",
            f"""
select
    'web'                              as channel,
    order_number                       as order_id,
    cast(null as bigint)               as store_sk,
    item_sk,
    bill_customer_sk                   as customer_sk,
    promo_sk,
    sold_date_sk,
    quantity, sales_price, ext_sales_price, ext_list_price, coupon_amt, net_paid, net_profit

from {{{{ ref('stg_tpcds__web_sales') }}}}
where sold_date_sk is not null
""",
            "Web sales lines in the shape shared by every channel.",
        ),
        Model(
            "int_tpcds__sales_all_channels",
            """
select * from {{ ref('int_tpcds__store_sales_lines') }}
union all
select * from {{ ref('int_tpcds__catalog_sales_lines') }}
union all
select * from {{ ref('int_tpcds__web_sales_lines') }}
""",
            "Every sales line from the three channels, one shape, one row per line.",
        ),
        Model(
            "int_tpcds__returns_all_channels",
            """
select 'store' as channel, ticket_number as order_id, item_sk, customer_sk, returned_date_sk,
       return_quantity, return_amt as return_amount, return_tax, net_loss, reason_sk
from {{ ref('stg_tpcds__store_returns') }}

union all

select 'catalog', order_number, item_sk, returning_customer_sk, returned_date_sk,
       return_quantity, return_amount, return_tax, net_loss, reason_sk
from {{ ref('stg_tpcds__catalog_returns') }}

union all

select 'web', order_number, item_sk, returning_customer_sk, returned_date_sk,
       return_quantity, return_amt, return_tax, net_loss, reason_sk
from {{ ref('stg_tpcds__web_returns') }}
""",
            "Every return from the three channels in one shape.",
        ),
        Model(
            "int_tpcds__inventory_snapshots",
            """
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
""",
            "Weekly inventory levels with the calendar date and item category attached.",
        ),
    ]


def marts():
    dims = [
        Model(
            "dim_tpcds_customer",
            """
select
    *,
    concat(first_name, ' ', last_name)                                   as full_name,
    case
        when birth_year is null then 'unknown'
        when birth_year >= 1980 then 'under 45'
        when birth_year >= 1960 then '45 to 64'
        else '65 and over'
    end                                                                   as age_band

from {{ ref('int_tpcds__customer_profile') }}
""",
            "One row per customer, with a name and an age band derived from the birth year.",
            grain=("customer_sk",),
            tests=not_null("customer_sk", "customer_id"),
        ),
        Model(
            "dim_tpcds_item",
            "select * from {{ ref('int_tpcds__item_hierarchy') }}",
            "One row per item.",
            grain=("item_sk",),
            tests=merge(not_null("item_sk"), {"current_price": [at_least(0)]}),
        ),
        Model(
            "dim_tpcds_date",
            "select * from {{ ref('int_tpcds__calendar') }}",
            "One row per calendar day.",
            grain=("date_sk",),
            tests=merge(not_null("date_sk", "calendar_date"), {"month": [at_least(1), ("dbt_utils.accepted_range", {"min_value": 1, "max_value": 12, "inclusive": "true"})]}),
        ),
        Model(
            "dim_tpcds_store",
            "select * from {{ ref('int_tpcds__store_dim') }}",
            "One row per store.",
            grain=("store_sk",),
            tests=not_null("store_sk"),
        ),
        Model(
            "dim_tpcds_warehouse",
            """
select warehouse_sk, warehouse_name, warehouse_sq_ft, city, state, country
from {{ ref('stg_tpcds__warehouse') }}
""",
            "One row per warehouse.",
            grain=("warehouse_sk",),
            tests=not_null("warehouse_sk"),
        ),
        Model(
            "dim_tpcds_promotion",
            """
select
    promo_sk,
    promo_name,
    purpose,
    cost,
    (case when channel_dmail   = 'Y' then 1 else 0 end)
  + (case when channel_email   = 'Y' then 1 else 0 end)
  + (case when channel_catalog = 'Y' then 1 else 0 end)
  + (case when channel_tv      = 'Y' then 1 else 0 end)
  + (case when channel_radio   = 'Y' then 1 else 0 end)
  + (case when channel_press   = 'Y' then 1 else 0 end)                  as channels_used

from {{ ref('stg_tpcds__promotion') }}
""",
            "One row per promotion, with how many marketing channels it used.",
            grain=("promo_sk",),
            tests=merge(not_null("promo_sk"), {"channels_used": [("dbt_utils.accepted_range", {"min_value": 0, "max_value": 6, "inclusive": "true"})]}),
        ),
    ]

    facts = [
        Model(
            "fct_tpcds_sales",
            """
select
    s.channel,
    s.order_id,
    s.item_sk,
    s.customer_sk,
    s.store_sk,
    s.promo_sk,
    s.sold_date_sk,
    c.calendar_date,
    c.year,
    c.month,
    c.quarter,
    c.day_name,
    c.is_weekend,
    s.quantity,
    s.sales_price,
    s.ext_sales_price,
    s.ext_list_price,
    s.coupon_amt,
    s.net_paid,
    s.net_profit,
    s.ext_list_price - s.ext_sales_price                                  as discount_amount

from {{ ref('int_tpcds__sales_all_channels') }} s
join {{ ref('int_tpcds__calendar') }} c on s.sold_date_sk = c.date_sk
""",
            "One row per sales line across store, catalog and web.",
            grain=("channel", "order_id", "item_sk"),
            tests=merge(
                not_null("channel", "order_id", "item_sk", "calendar_date"),
                {
                    "channel": [accepted_values("store", "catalog", "web")],
                    "item_sk": [relationship("dim_tpcds_item", "item_sk")],
                    "sold_date_sk": [relationship("dim_tpcds_date", "date_sk")],
                    "customer_sk": [relationship("dim_tpcds_customer", "customer_sk")],
                    "quantity": [at_least(0)],
                },
            ),
        ),
        Model(
            "fct_tpcds_store_sales",
            """
select
    s.order_id                        as ticket_number,
    s.item_sk,
    s.customer_sk,
    s.store_sk,
    s.promo_sk,
    c.calendar_date,
    c.year,
    c.month,
    s.quantity,
    s.ext_sales_price,
    s.net_paid,
    s.net_profit

from {{ ref('int_tpcds__store_sales_lines') }} s
join {{ ref('int_tpcds__calendar') }} c on s.sold_date_sk = c.date_sk
""",
            "One row per store sales line.",
            grain=("ticket_number", "item_sk"),
            tests=merge(
                not_null("ticket_number", "item_sk"),
                {"store_sk": [relationship("dim_tpcds_store", "store_sk")]},
            ),
        ),
        Model(
            "fct_tpcds_returns",
            """
select
    r.channel,
    r.order_id,
    r.item_sk,
    r.customer_sk,
    c.calendar_date,
    c.year,
    c.month,
    r.return_quantity,
    r.return_amount,
    r.return_tax,
    r.net_loss,
    r.reason_sk

from {{ ref('int_tpcds__returns_all_channels') }} r
join {{ ref('int_tpcds__calendar') }} c on r.returned_date_sk = c.date_sk
""",
            "One row per returned line across the three channels.",
            grain=("channel", "order_id", "item_sk"),
            tests=merge(
                not_null("channel", "order_id", "item_sk"),
                {"item_sk": [relationship("dim_tpcds_item", "item_sk")]},
            ),
        ),
        Model(
            "fct_tpcds_inventory",
            "select * from {{ ref('int_tpcds__inventory_snapshots') }}",
            "One row per item, warehouse and week: how much stock was on hand.",
            grain=("date_sk", "item_sk", "warehouse_sk"),
            tests=merge(
                not_null("date_sk", "item_sk", "warehouse_sk"),
                {
                    "item_sk": [relationship("dim_tpcds_item", "item_sk")],
                    "warehouse_sk": [relationship("dim_tpcds_warehouse", "warehouse_sk")],
                },
            ),
        ),
    ]

    aggs = [
        Model(
            "agg_tpcds_sales_by_month_channel",
            """
with monthly as (

    select
        year, month, channel,
        sum(ext_sales_price)          as revenue,
        sum(net_profit)               as profit,
        sum(quantity)                 as units,
        count(distinct order_id)      as orders
    from {{ ref('fct_tpcds_sales') }}
    group by year, month, channel

)

select
    *,
    sum(revenue) over (partition by channel, year order by month)                        as ytd_revenue,
    revenue / nullif(sum(revenue) over (partition by year, month), 0)                    as channel_share

from monthly
""",
            "Revenue, profit, units and orders per month and channel, with a running year to date and each channel's share of the month.",
            grain=("year", "month", "channel"),
            tests=merge(not_null("year", "month", "channel", "revenue"), {"orders": [at_least(0)]}),
        ),
        Model(
            "agg_tpcds_sales_by_category_year",
            """
select
    i.category,
    s.year,
    sum(s.ext_sales_price)                                                              as revenue,
    sum(s.net_profit)                                                                   as profit,
    sum(s.quantity)                                                                     as units,
    rank() over (partition by s.year order by sum(s.ext_sales_price) desc)              as revenue_rank

from {{ ref('fct_tpcds_sales') }} s
join {{ ref('dim_tpcds_item') }} i on s.item_sk = i.item_sk
where i.category is not null
group by i.category, s.year
""",
            "Revenue and profit per item category and year, ranked within the year.",
            grain=("category", "year"),
            tests=not_null("category", "year", "revenue"),
        ),
        Model(
            "agg_tpcds_sales_by_state",
            """
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
""",
            "Revenue, customers and orders per customer state and year.",
            grain=("state", "year"),
            tests=not_null("state", "year"),
        ),
        Model(
            "agg_tpcds_top_items_by_year",
            """
with ranked as (

    select
        year,
        item_sk,
        sum(ext_sales_price)                                                            as revenue,
        row_number() over (partition by year order by sum(ext_sales_price) desc)         as revenue_rank
    from {{ ref('fct_tpcds_sales') }}
    group by year, item_sk

)

select * from ranked where revenue_rank <= 100
""",
            "The hundred best-selling items of each year by revenue.",
            grain=("year", "item_sk"),
            tests=merge(not_null("year", "item_sk"), {"revenue_rank": [("dbt_utils.accepted_range", {"min_value": 1, "max_value": 100, "inclusive": "true"})]}),
        ),
        Model(
            "agg_tpcds_yoy_growth",
            """
with by_year as (

    select category, year, revenue from {{ ref('agg_tpcds_sales_by_category_year') }}

)

select
    category,
    year,
    revenue,
    lag(revenue) over (partition by category order by year)                              as prior_year_revenue,
    (revenue - lag(revenue) over (partition by category order by year))
        / nullif(lag(revenue) over (partition by category order by year), 0)             as yoy_growth

from by_year
""",
            "Year over year revenue growth per item category.",
            grain=("category", "year"),
            tests=not_null("category", "year"),
        ),
        Model(
            "agg_tpcds_customer_rfm",
            """
with customer_activity as (

    select
        customer_sk,
        max(calendar_date)                  as last_purchase_date,
        count(distinct order_id)            as frequency,
        sum(ext_sales_price)                as monetary
    from {{ ref('fct_tpcds_sales') }}
    where customer_sk is not null
    group by customer_sk

),

with_recency as (

    select
        *,
        datediff((select max(calendar_date) from {{ ref('fct_tpcds_sales') }}), last_purchase_date) as recency_days
    from customer_activity

)

select
    *,
    ntile(5) over (order by recency_days desc)     as recency_score,
    ntile(5) over (order by frequency)             as frequency_score,
    ntile(5) over (order by monetary)              as monetary_score

from with_recency
""",
            "Recency, frequency and monetary value per customer, each scored one to five.",
            grain=("customer_sk",),
            tests=merge(
                not_null("customer_sk", "recency_days", "frequency", "monetary"),
                {
                    "recency_score": [("dbt_utils.accepted_range", {"min_value": 1, "max_value": 5, "inclusive": "true"})],
                    "recency_days": [at_least(0)],
                },
            ),
        ),
        Model(
            "agg_tpcds_customer_ltv",
            """
select
    customer_sk,
    min(calendar_date)                                        as first_purchase_date,
    max(calendar_date)                                        as last_purchase_date,
    count(distinct order_id)                                  as orders,
    sum(ext_sales_price)                                      as revenue,
    sum(net_profit)                                           as profit,
    percent_rank() over (order by sum(ext_sales_price))       as revenue_percentile

from {{ ref('fct_tpcds_sales') }}
where customer_sk is not null
group by customer_sk
""",
            "Lifetime revenue and profit per customer, with where that customer sits in the revenue distribution.",
            grain=("customer_sk",),
            tests=merge(
                not_null("customer_sk", "revenue"),
                {"revenue_percentile": [("dbt_utils.accepted_range", {"min_value": 0, "max_value": 1, "inclusive": "true"})]},
            ),
        ),
        Model(
            "agg_tpcds_return_rate_by_item",
            """
with sold as (

    select item_sk, sum(quantity) as units_sold
    from {{ ref('fct_tpcds_sales') }}
    group by item_sk

),

returned as (

    select item_sk, sum(return_quantity) as units_returned
    from {{ ref('fct_tpcds_returns') }}
    group by item_sk

)

select
    sold.item_sk,
    sold.units_sold,
    coalesce(returned.units_returned, 0)                                                as units_returned,
    coalesce(returned.units_returned, 0) / nullif(sold.units_sold, 0)                   as return_rate

from sold
left join returned on sold.item_sk = returned.item_sk
where sold.units_sold > 0
""",
            "The share of units sold that came back, per item.",
            grain=("item_sk",),
            tests=merge(not_null("item_sk", "units_sold"), {"units_returned": [at_least(0)]}),
        ),
        Model(
            "agg_tpcds_store_performance",
            """
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
""",
            "Revenue, profit and revenue per square foot for each store and year.",
            grain=("store_sk", "year"),
            tests=not_null("store_sk", "year", "revenue"),
        ),
        Model(
            "agg_tpcds_basket_size",
            """
with baskets as (

    select
        channel, year, month, order_id,
        count(*)                       as items,
        sum(ext_sales_price)           as basket_value
    from {{ ref('fct_tpcds_sales') }}
    group by channel, year, month, order_id

)

select
    channel, year, month,
    count(*)                                        as orders,
    avg(items)                                      as avg_items,
    percentile_approx(items, 0.5)                   as median_items,
    avg(basket_value)                               as avg_basket_value,
    max(basket_value)                               as max_basket_value

from baskets
group by channel, year, month
""",
            "How many items and how much money a typical order holds, per channel and month.",
            grain=("channel", "year", "month"),
            tests=merge(not_null("channel", "year", "month", "orders"), {"avg_items": [at_least(1)]}),
        ),
        Model(
            "agg_tpcds_promo_effectiveness",
            """
select
    coalesce(cast(s.promo_sk as string), 'none')                       as promo,
    count(distinct s.order_id)                                         as orders,
    sum(s.quantity)                                                    as units,
    sum(s.ext_sales_price)                                             as revenue,
    sum(s.discount_amount) / nullif(sum(s.ext_list_price), 0)          as discount_rate

from {{ ref('fct_tpcds_sales') }} s
group by coalesce(cast(s.promo_sk as string), 'none')
""",
            "Orders, revenue and the discount rate for each promotion, and for sales with none.",
            grain=("promo",),
            tests=not_null("promo", "revenue"),
        ),
        Model(
            "agg_tpcds_price_band_mix",
            """
select
    channel,
    case
        when sales_price < 10  then '1 under 10'
        when sales_price < 50  then '2 10 to 50'
        when sales_price < 100 then '3 50 to 100'
        when sales_price < 200 then '4 100 to 200'
        else '5 200 and over'
    end                                                                 as price_band,
    sum(quantity)                                                       as units,
    sum(ext_sales_price)                                                as revenue,
    avg(discount_amount / nullif(ext_list_price, 0))                    as avg_discount_rate

from {{ ref('fct_tpcds_sales') }}
where sales_price is not null
group by channel, 2
""",
            "Units and revenue by channel and price band.",
            grain=("channel", "price_band"),
            tests=not_null("channel", "price_band"),
        ),
        Model(
            "agg_tpcds_demographic_spend",
            """
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
""",
            "Spending by gender, marital status, education and year.",
            grain=("gender", "marital_status", "education_status", "year"),
            tests=not_null("gender", "year"),
        ),
        Model(
            "agg_tpcds_weekday_pattern",
            """
select
    channel,
    day_name,
    is_weekend,
    count(distinct order_id)        as orders,
    sum(ext_sales_price)            as revenue

from {{ ref('fct_tpcds_sales') }}
group by channel, day_name, is_weekend
""",
            "Orders and revenue by channel and day of the week.",
            grain=("channel", "day_name"),
            tests=not_null("channel", "day_name"),
        ),
        Model(
            "agg_tpcds_inventory_turnover",
            """
with stock as (

    select year, month, category, avg(quantity_on_hand) as avg_on_hand
    from {{ ref('fct_tpcds_inventory') }}
    where category is not null
    group by year, month, category

),

sold as (

    select s.year, s.month, i.category, sum(s.quantity) as units_sold
    from {{ ref('fct_tpcds_sales') }} s
    join {{ ref('dim_tpcds_item') }} i on s.item_sk = i.item_sk
    where i.category is not null
    group by s.year, s.month, i.category

)

select
    stock.year, stock.month, stock.category,
    stock.avg_on_hand,
    sold.units_sold,
    sold.units_sold / nullif(stock.avg_on_hand, 0)      as turnover

from stock
join sold on stock.year = sold.year and stock.month = sold.month and stock.category = sold.category
""",
            "How many times the average stock was sold, per category and month.",
            grain=("year", "month", "category"),
            tests=not_null("year", "month", "category"),
        ),
        Model(
            "agg_tpcds_cohort_retention",
            """
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
""",
            "For customers grouped by the month of their first purchase, how many bought again in each later month.",
            grain=("cohort_index", "months_since_first"),
            tests=merge(not_null("cohort_index", "months_since_first"), {"months_since_first": [at_least(0)]}),
        ),
    ]
    return dims + facts + aggs


def generate():
    n = write_group("intermediate/tpcds", "_int_tpcds__models.yml", intermediate())
    n += write_group("marts/tpcds", "_tpcds__models.yml", marts())
    return n
