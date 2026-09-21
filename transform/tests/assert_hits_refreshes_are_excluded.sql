select count(*) as refresh_rows
from {{ ref('int_hits__events') }}
where is_page_refresh
having count(*) > 0
