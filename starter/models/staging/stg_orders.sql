with source_data as (
    select *
    from {{ source('app', 'raw_orders') }}
)

select
    cast(trim(order_id) as string) as order_id,
    cast(trim(customer_id) as string) as customer_id,
    cast(order_date as date) as order_date,
    lower(trim(status)) as status,
    cast(amount as numeric) as amount
from source_data
where order_id is not null
