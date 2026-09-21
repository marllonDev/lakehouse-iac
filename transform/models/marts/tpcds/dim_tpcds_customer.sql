select
    *,
    concat(first_name, ' ', last_name)                                   as full_name,
    case
        when birth_year is null then 'unknown'
        when birth_year >= 1980 then 'under 45'
        when birth_year >= 1960 then '45 to 64'
        else '65 and over'
    end                                                                   as age_band

from {{ ref('int_tpcds__customer_profile') }}
