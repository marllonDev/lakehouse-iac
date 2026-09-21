select
    p.property_type,
    count(*)                                  as reviews,
    avg(r.rating)                             as avg_rating,
    percentile_approx(r.rating, 0.5)          as median_rating,
    stddev(r.rating)                          as rating_stddev

from {{ ref('fct_wb_reviews') }} r
join {{ ref('dim_wb_property') }} p on r.property_id = p.property_id
group by p.property_type
