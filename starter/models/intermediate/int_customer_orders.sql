with orders as (
    select *
    from {{ ref('stg_orders') }}
),

customers as (
    select *
    from {{ ref('stg_customers') }}
)

select
    orders.order_id,
    orders.customer_id,
    customers.country,
    customers.segment,
    orders.order_date,
    orders.status,
    orders.amount,
    case
        when customers.customer_id is not null
             and orders.amount >= 0
        then true
        else false
    end as is_valid
from orders
left join customers
    on orders.customer_id = customers.customer_id
