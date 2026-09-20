select o.order_key, o.customer_key
from {{ ref('fct_orders') }} o
left join {{ ref('dim_customers') }} c on o.customer_key = c.customer_key
where c.customer_key is null
