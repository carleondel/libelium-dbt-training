# Solutions — DuckDB sandbox

This file is the instructor/audit reference for the exercises in
[`EXERCISE_GUIDE.md`](EXERCISE_GUIDE.md). The learner-facing challenge is
deliberately open-ended; use these solutions to verify the required outcomes,
not to force one exact naming choice for every derived column.

Prerequisite: `uv` must be installed and available on `PATH`.

Create a dedicated disposable instructor copy and enter it:

```bash
cd "$HOME/code/libelium-dbt-training"
SOLUTION_DIR="$(./new-lab-workspace.sh instructor-solution --path-only)"
cd "$SOLUTION_DIR"

uv sync --frozen
uv run dbt --version
uv run python -c "import duckdb; print(duckdb.__version__)"
```

The included `profiles.yml` points to the local DuckDB file
`target/sandbox.duckdb`, so no cloud credentials are needed.

For visual warehouse inspection, run
`uv run python scripts/start_duckdb_ui.py` after a dbt build. Stop it with
`Ctrl+C` before the next build to release the database file. Keep this
instructor solution copy separate from the learner workspace.

## 1. Baseline verification

Run the starter before changing any model:

```bash
uv run dbt clean --profiles-dir .
uv run dbt seed --profiles-dir . --full-refresh
uv run dbt build --profiles-dir . --select +fct_orders+
```

Expected result: the starter order branch passes, and `fct_orders` contains
one row per valid order. The payment branch is intentionally not part of this
baseline fact yet.

Useful checks:

```bash
uv run python -c "import duckdb; c=duckdb.connect('target/sandbox.duckdb'); print(c.sql('select count(*) as row_count, count(distinct order_id) as orders from fct_orders').show())"
uv run python -c "import duckdb; c=duckdb.connect('target/sandbox.duckdb'); print(c.sql('select * from fct_orders order by order_id').show())"
```

## 2. Micro-lab solution

The exercise asks for one small, readable change to the existing order fact.
One valid answer is a derived amount that only counts completed orders.

In `models/marts/fct_orders.sql`, add the expression after
`amount as order_amount,`:

```sql
case
    when status = 'completed' then amount
    else 0
end as completed_order_amount
```

The resulting model can be:

```sql
{{ config(materialized='table') }}

select
    order_id,
    customer_id,
    order_date,
    status,
    amount as order_amount,
    case
        when status = 'completed' then amount
        else 0
    end as completed_order_amount
from {{ ref('int_customer_orders') }}
where is_valid = true
```

Validate the change:

```bash
uv run dbt parse --profiles-dir .
uv run dbt build --profiles-dir . --select +fct_orders+
uv run python -c "import duckdb; c=duckdb.connect('target/sandbox.duckdb'); print(c.sql('select order_id, status, order_amount, completed_order_amount from fct_orders order by order_id').show())"
uv run python -c "import duckdb; c=duckdb.connect('target/sandbox.duckdb'); print(c.sql('select count(*) as row_count, count(distinct order_id) as orders from fct_orders').show())"
```

What to audit:

- The new column is derived from existing model columns.
- No new `ref()` is required, so the DAG does not gain an edge.
- The model still has one row per order.
- The warehouse relation is still `fct_orders`, rebuilt from the changed SQL.

## 3. Capstone required solution

The capstone has two separate grain operations:

```text
payment snapshots
  → latest snapshot per payment_id
  → aggregate to one row per order_id
  → left join to fct_orders
```

This distinction matters. Deduplicating `payment_id` removes repeated
snapshots, but an order may still have several legitimate payment keys. Only
the aggregation guarantees one row per order.

### Step A — aggregate payments to order grain

Replace the contents of `models/intermediate/int_order_payments.sql` with:

```sql
{{ config(materialized='table') }}

with payment_snapshots as (
    select *
    from {{ ref('stg_payments') }}
),

latest_payment_snapshot as (
    select
        order_id,
        payment_id,
        payment_status,
        payment_amount,
        payment_updated_at,
        row_number() over (
            partition by payment_id
            order by payment_updated_at desc
        ) as snapshot_rank
    from payment_snapshots
),

deduplicated_payments as (
    select *
    from latest_payment_snapshot
    where snapshot_rank = 1
)

select
    order_id,
    sum(case when payment_status = 'paid' then payment_amount else 0 end) as paid_amount,
    max(payment_updated_at) as latest_payment_updated_at,
    count(*) as payment_attempt_count
from deduplicated_payments
group by order_id
```

The rule keeps the latest snapshot for each `payment_id`, including the
fixture where `p_2001` appears first as failed and later as paid. It then sums
the final paid records at `order_id` grain. Orders without payments do not
appear in this intermediate relation, which is why the fact join must be a
`left join`.

How the window function works:

- `over (...)` defines the set and ordering used by the window calculation;
- `partition by payment_id` restarts numbering for each payment key;
- `order by payment_updated_at desc` places the newest snapshot first;
- `row_number()` assigns `1, 2, 3...` inside each payment partition;
- filtering to `snapshot_rank = 1` keeps only the latest snapshot.

Build this intermediate model before touching the fact:

```bash
uv run dbt build --profiles-dir . --select +int_order_payments
uv run python scripts/start_duckdb_ui.py
```

To demonstrate the ranking directly in a DuckDB UI notebook, run:

```sql
select
    order_id,
    payment_id,
    payment_status,
    payment_amount,
    payment_updated_at,
    row_number() over (
        partition by payment_id
        order by payment_updated_at desc
    ) as snapshot_rank
from stg_payments
where payment_id = 'p_2001'
order by payment_updated_at desc;
```

The newest `p_2001` row receives rank 1. Close the UI with `Ctrl+C` before
the next dbt build.

### Step B — join the payment summary to the fact

Replace the contents of `models/marts/fct_orders.sql` with:

```sql
{{ config(materialized='table') }}

select
    orders.order_id,
    orders.customer_id,
    orders.order_date,
    orders.status,
    orders.amount as order_amount,
    coalesce(payments.paid_amount, 0) as paid_amount
from {{ ref('int_customer_orders') }} as orders
left join {{ ref('int_order_payments') }} as payments
    on orders.order_id = payments.order_id
where orders.is_valid = true
```

The `left join` preserves valid orders with no payment records. The
`coalesce` makes their derived paid amount explicit as zero rather than null.

### Step C — document the final output

In `models/schema.yml`, replace the starter `int_order_payments` model block
with this aggregated definition:

```yaml
  - name: int_order_payments
    description: "Payment snapshots deduplicated by payment_id and aggregated to one row per order."
    columns:
      - name: order_id
        description: Order associated with the payment summary.
        data_tests:
          - not_null
      - name: paid_amount
        description: Sum of the latest paid payment snapshots at order grain.
      - name: latest_payment_updated_at
        description: Latest payment snapshot timestamp for the order.
      - name: payment_attempt_count
        description: Number of deduplicated payment records at order grain.
        data_tests:
          - not_null
```

`payment_id` is intentionally absent from this final YAML block. The model has
been aggregated to `order_id` grain and one order can contain multiple payment
keys, so there is no single truthful `payment_id` column to expose. It still
exists in the deduplication CTE before the order-level aggregation.

Add this column definition under the existing `fct_orders` columns:

```yaml
      - name: paid_amount
        description: Amount from the latest paid payment snapshots.
```

Keep the existing singular test file
`tests/int_order_payments_one_row_per_order.sql`. It should fail whenever the
intermediate payment model emits more than one row for an order.

Validate the required capstone:

```bash
uv run dbt parse --profiles-dir .
uv run dbt build --profiles-dir . --select +fct_orders+
uv run python -c "import duckdb; c=duckdb.connect('target/sandbox.duckdb'); print(c.sql('select count(*) as row_count, count(distinct order_id) as orders from fct_orders').show()); print(c.sql('select order_id, order_amount, paid_amount from fct_orders order by order_id').show())"
```

Expected checks:

- `int_order_payments` has one row per `order_id`.
- `fct_orders` has no duplicated `order_id` values.
- Valid orders with no payments remain in `fct_orders` with `paid_amount = 0`.
- The singular one-row-per-order test passes.

## 4. Optional stretch solution — customer dimension

Create `models/marts/dim_customers.sql`:

```sql
{{ config(materialized='table') }}

select
    customer_id,
    country,
    segment,
    signup_date
from {{ ref('stg_customers') }}
```

Add this model block to `models/schema.yml`:

```yaml
  - name: dim_customers
    description: "Customer dimension. Grain: one row per customer."
    columns:
      - name: customer_id
        description: Stable customer identifier.
        data_tests:
          - not_null
          - unique
      - name: country
        description: Customer country.
      - name: segment
        description: Customer segment.
```

Build both branches:

```bash
uv run dbt build --profiles-dir . --select +dim_customers+ +fct_orders+
```

Then answer an analytical question by joining the fact and dimension. For
example:

```sql
select
    customers.country,
    customers.segment,
    count(*) as order_count,
    sum(orders.order_amount) as revenue
from fct_orders as orders
join dim_customers as customers using (customer_id)
group by 1, 2
order by revenue desc;
```

The stretch adds descriptive context without changing the fact grain. It is
not required to complete the payment challenge.

## 5. Final audit queries

Run these queries after the required solution:

```bash
uv run python -c "import duckdb; c=duckdb.connect('target/sandbox.duckdb'); print('fct_orders grain:'); print(c.sql('select count(*) as row_count, count(distinct order_id) as distinct_orders from fct_orders').show()); print('payment grain:'); print(c.sql('select count(*) as row_count, count(distinct order_id) as distinct_orders from int_order_payments').show()); print('orders without payments:'); print(c.sql('select count(*) as orders_without_payment from fct_orders where paid_amount = 0').show())"
```

To inspect the deliberate edge cases in the seeds:

```bash
uv run python -c "import duckdb; c=duckdb.connect('target/sandbox.duckdb'); print('duplicate payment snapshots:'); print(c.sql(\"select payment_id, count(*) as snapshot_count from raw_payments group by payment_id having count(*) > 1\").show()); print('multiple payment keys per order:'); print(c.sql(\"select order_id, count(distinct payment_id) as payment_keys from raw_payments group by order_id having count(distinct payment_id) > 1\").show()); print('orders without payments:'); print(c.sql(\"select o.order_id from raw_orders o left join raw_payments p on o.id = p.order_id where p.order_id is null order by o.order_id\").show())"
```

The expected learning evidence is not a particular revenue number. It is the
chain of reasoning: define the grain, deduplicate snapshots, aggregate to the
fact grain, preserve unmatched orders with a left join, document the output,
and prove the grain with a test.

## 6. Debrief answers

1. **Why deduplicate and aggregate?** Deduplication removes stale repeated
   snapshots of the same payment key. Aggregation then changes the remaining
   payment-key rows to one row per order, matching the fact grain.
2. **What would a direct join do?** It could produce several fact rows for one
   order, duplicating order amounts and corrupting downstream sums.
3. **Why a left join?** Some valid orders have no payment record. A left join
   preserves those orders; an inner join would silently remove them.
4. **Which test best proves grain?** The existing singular
   `int_order_payments_one_row_per_order` test directly finds duplicated
   `order_id` values. `unique` on `fct_orders.order_id` proves the final fact
   grain as a second check.
5. **What caveat applies to `paid_amount`?** It sums only payment keys whose
   latest snapshot is `paid`. It is a training definition, not necessarily
   recognized revenue, and it does not model currency conversion, partial
   refunds, chargebacks, taxes or later-arriving snapshots.

## 7. Discard the solution workspace and start again

Close DuckDB UI, then run:

```bash
cd "$HOME/code/libelium-dbt-training"
./discard-lab-workspace.sh "$SOLUTION_DIR"

SOLUTION_DIR="$(./new-lab-workspace.sh instructor-solution --path-only)"
cd "$SOLUTION_DIR"
uv sync --frozen
uv run dbt seed --profiles-dir . --full-refresh
uv run dbt build --profiles-dir . --select +fct_orders+
```
