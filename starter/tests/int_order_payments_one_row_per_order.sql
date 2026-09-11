select
    order_id
from {{ ref('int_order_payments') }}
group by order_id
having count(*) > 1
