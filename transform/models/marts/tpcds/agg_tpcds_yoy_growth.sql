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
