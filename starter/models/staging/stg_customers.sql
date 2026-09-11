with source_data as (
    select *
    from {{ source('app', 'raw_customers') }}
)

select
    cast(trim(customer_id) as string) as customer_id,
    upper(trim(country)) as country,
    lower(trim(segment)) as segment,
    cast(signup_date as date) as signup_date
from source_data
