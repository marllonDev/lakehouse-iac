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
