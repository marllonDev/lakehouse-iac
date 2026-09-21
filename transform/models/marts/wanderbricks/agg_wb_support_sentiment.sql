select
    sender,
    sentiment,
    count(*)                                                                        as messages,
    count(distinct ticket_id)                                                       as tickets,
    count(*) / sum(count(*)) over (partition by sender)                             as share_of_sender

from {{ ref('fct_wb_support_messages') }}
where sentiment is not null
group by sender, sentiment
