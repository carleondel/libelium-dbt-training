-- Starter model: the capstone asks learners to resolve payment snapshots and
-- aggregate the result to one row per order.
-- The current version intentionally preserves source snapshots so that both
-- the latest-payment rule and the final order-grain aggregation are visible.
select
    order_id,
    payment_id,
    payment_status,
    payment_amount,
    payment_updated_at,
    payment_method
from {{ ref('stg_payments') }}
