select
    user_id, name, country, user_type, created_at, is_business,
    datediff(current_date(), cast(created_at as date))       as tenure_days

from {{ ref('stg_wanderbricks__users') }}
