with ranked as (

    select
        d.part_key,
        d.demand_year,
        d.units_sold,
        d.net_revenue,
        row_number() over (partition by d.demand_year order by d.net_revenue desc) as revenue_rank

    from {{ ref('int_tpch__part_demand') }} d

)

select r.*, p.part_name, p.brand
from ranked r
inner join {{ ref('dim_tpch_part') }} p on r.part_key = p.part_key
where r.revenue_rank <= 25
