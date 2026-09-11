select
    cast(trim(payment_id) as string) as payment_id,
    cast(trim(order_id) as string) as order_id,
    lower(trim(payment_status)) as payment_status,
    cast(payment_amount as numeric) as payment_amount,
    cast(payment_updated_at as timestamp) as payment_updated_at,
    lower(trim(payment_method)) as payment_method
from {{ source('app', 'raw_payments') }}
