select
    is_mobile_device,
    mobile_phone_model,
    os_id,
    count(*)                                            as events,
    count(distinct user_id)                             as users

from {{ ref('int_hits__events') }}
group by is_mobile_device, mobile_phone_model, os_id
