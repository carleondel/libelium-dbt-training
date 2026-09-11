{{ config(materialized='table') }}

select
    order_id,
    customer_id,
    order_date,
    status,
    amount as order_amount
from {{ ref('int_customer_orders') }}
where is_valid = true
