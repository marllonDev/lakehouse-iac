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
