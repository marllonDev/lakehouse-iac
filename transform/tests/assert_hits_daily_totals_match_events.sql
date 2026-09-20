select fct.events, direct.events as direct_events
from (select sum(events) as events from {{ ref('fct_hits_daily') }}) fct
cross join (select count(*) as events from {{ ref('int_hits__events') }}) direct
where fct.events <> direct.events
