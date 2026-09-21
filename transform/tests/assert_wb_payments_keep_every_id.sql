-- The payments fact deduplicates on the id, so it must still hold each id once.
select source.ids as source_ids, fact.ids as fact_ids
from (select count(distinct payment_id) as ids from {{ ref('stg_wanderbricks__payments') }}) source
cross join (select count(distinct payment_id) as ids from {{ ref('fct_wb_payments') }}) fact
where source.ids <> fact.ids
