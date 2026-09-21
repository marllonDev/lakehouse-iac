select
    l.ticket_id,
    l.user_id,
    l.support_agent_id,
    cast(l.created_at as timestamp)              as ticket_created_at,
    m.sender,
    m.sentiment,
    m.message,
    cast(m.`timestamp` as timestamp)             as message_at

from {{ ref('stg_wanderbricks__customer_support_logs') }} l
lateral view explode(l.messages) exploded as m
