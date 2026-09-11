# Exercise guide — DuckDB sandbox

This guide is for validating the training exercises locally. Create a
disposable copy from the repository root and work inside the printed path:

```bash
cd "$HOME/code/libelium-dbt-training"
LAB_DIR="$(./new-lab-workspace.sh your-name --path-only)"
cd "$LAB_DIR"
pwd
```

Never solve the exercises directly in the reusable
`starter/` master.

Prerequisite: make sure `uv --version` works. If it does not, install `uv`
before creating the lab.

macOS/Linux:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
exec "$SHELL" -l
uv --version
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
uv --version
```

## 1. Set up and prove the starter works

```bash
uv sync --frozen
uv run dbt --version
uv run python -c "import duckdb; print(duckdb.__version__)"
uv run dbt seed --profiles-dir . --full-refresh
uv run dbt build --profiles-dir . --select +fct_orders+
```

Why these flags and wrappers matter:

- `uv sync --frozen` creates/populates `.venv` from `uv.lock`. An empty
  environment cannot run dbt or import DuckDB.
- `uv run ...` executes inside that synchronized environment. Plain `dbt ...`
  can accidentally resolve to dbt from another repository or a global shim.
- `--profiles-dir .` forces dbt to use this sandbox's local `profiles.yml`,
  which points to `target/sandbox.duckdb`.

If `uv run python scripts/start_duckdb_ui.py` reports that `duckdb` cannot be
imported, the disposable environment was not synchronized. Do not activate an
environment from another repository. Run:

```bash
uv sync --frozen
uv run python -c "import duckdb; print(duckdb.__version__)"
uv run python scripts/start_duckdb_ui.py
```

The baseline should finish successfully. The starter fact is one row per valid
order. The payment branch is intentionally unfinished and is not yet joined
to `fct_orders`.

Inspect the baseline before editing anything:

```bash
uv run python scripts/start_duckdb_ui.py
```

In DuckDB UI, expand `sandbox` → `main`, open `fct_orders`, and use **Preview
data**. Stop the UI with `Ctrl+C` before the next dbt command so the database
file is not held open by another process.

In a UI notebook run:

```sql
select * from raw_orders order by id limit 5;
select * from stg_orders order by order_id limit 5;
select * from fct_orders order by order_id limit 5;
```

This establishes the before-state: raw source, standardized staging model and
final warehouse fact.

## 2. Micro-lab: make one safe change

Close DuckDB UI with `Ctrl+C`. Open `models/marts/fct_orders.sql` and add one
simple derived column:

```sql
case
    when status = 'completed' then amount
    else 0
end as completed_order_amount
```

`completed_order_amount` means: keep the order amount when the order status is
`completed`; otherwise expose zero. It is a small teaching example of turning
a row attribute into a reusable derived measure. It is not an official
accounting or revenue rule.

Then run:

```bash
uv run dbt parse --profiles-dir .
uv run dbt build --profiles-dir . --select +fct_orders+
uv run python scripts/start_duckdb_ui.py
```

Run this query in a UI notebook:

```sql
select order_id, status, order_amount, completed_order_amount
from fct_orders
order by order_id;
```

Check that the model still has one row per order and explain which upstream
columns your new expression uses.

`dbt parse` reads project files, renders enough Jinja to understand resources,
validates references/configuration, and writes graph metadata such as the
manifest. It does not execute model SQL or create warehouse relations. The
following `dbt build` is what rebuilds the selected models and runs their
tests.

## 3. Capstone: add paid amount to the order fact

### Goal and order of work

The visible result must be a new `paid_amount` column in `fct_orders`, while
`fct_orders` remains exactly one row per valid order. Start in this order:

1. inspect the deliberate duplicate snapshots in `raw_payments`;
2. complete and build `int_order_payments` at one row per order;
3. inspect that intermediate result in DuckDB UI;
4. join it into `fct_orders` with a `left join` and `coalesce`;
5. build the full branch, inspect the final fact and check tests;
6. only then attempt the optional customer dimension.

Read [`SOLUTIONS.md`](SOLUTIONS.md) Step A or Step B if blocked. The solution
is a permitted hint, not a failure condition.

### Step A — resolve payment grain

Edit `models/intermediate/int_order_payments.sql`:

1. Read `stg_payments`.
2. Use `row_number()` over `partition by payment_id`, ordered by
   `payment_updated_at desc`.
3. Keep only the latest snapshot for each `payment_id`.
4. Aggregate the deduplicated rows to `order_id` grain.
5. Calculate at least one payment-derived measure, such as the sum of rows
   whose final status is `paid`.

The final model must expose one row per `order_id`. A valid shape is:

```text
payment snapshots
  → latest row per payment_id
  → one row per order_id
```

Do not skip the second step: one order can have several legitimate payment
attempts, so deduplicating `payment_id` alone does not guarantee order grain.

Build and inspect this model before changing the fact:

```bash
uv run dbt build --profiles-dir . --select +int_order_payments
uv run python scripts/start_duckdb_ui.py
```

In DuckDB UI verify one row per order:

```sql
select count(*) as row_count,
       count(distinct order_id) as distinct_orders
from int_order_payments;
```

Close the UI with `Ctrl+C` before continuing.

### Step B — extend the fact

Edit `models/marts/fct_orders.sql`:

1. Join the completed payment model to the existing order fact logic.
2. Add `paid_amount` from `int_order_payments`.
3. Keep `where is_valid = true`.
4. Do not introduce duplicate `order_id` values.
5. Document the new fact column in `models/schema.yml`.

Some orders have no payment rows. Use a `left join` and decide how to handle
the resulting null (for example, `coalesce` it to zero). Verify that all valid
orders remain in the fact instead of silently disappearing.

Update the `int_order_payments` section of `models/schema.yml` so its documented
columns match the final aggregated output. Add or preserve a meaningful test
for one row per order.

Run the full branch:

```bash
uv run dbt parse --profiles-dir .
uv run dbt build --profiles-dir . --select +fct_orders+
```

The build should pass the model tests and the singular
`int_order_payments_one_row_per_order` test.

### Step C — optional stretch dimension for early finishers

Create `models/marts/dim_customers.sql` from `stg_customers` with one row per
customer. Document its grain and add key tests in `models/schema.yml`. Then
answer one question by joining it to `fct_orders`, for example revenue or order
count by `country` or `segment`.

```bash
uv run dbt build --profiles-dir . --select +dim_customers+ +fct_orders+
```

“Stretch” means an optional extension for learners who finish the required
payment work early. It is not required to pass the Capstone. The stretch is
about model structure and grain, not complex SQL.

## 4. Inspect the output

```bash
uv run python scripts/start_duckdb_ui.py
```

Use the relation summary to inspect columns and types, then run:

```sql
select count(*) as row_count,
       count(distinct order_id) as distinct_orders
from fct_orders;

select *
from fct_orders
order by order_id;
```

Close the UI before rebuilding. If you need a full reset, discard the
disposable workspace and run `new-lab-workspace.sh` again.

When reviewing your work, be able to answer:

- What does one row in each model represent?
- Where does each input come from?
- Which `ref()` edge did the Capstone add?
- Which test proves the intended grain?
- What caveat would you mention about the payment data?

For the full solution, including the exact SQL/YAML and reset instructions,
see [`SOLUTIONS.md`](SOLUTIONS.md). Try the exercise first if you want to
audit whether the instructions are sufficiently clear for a learner.

## 5. Start over from a clean workspace

First close DuckDB UI with `Ctrl+C`. Then run these exact commands from the
same shell that contains `LAB_DIR`:

```bash
cd "$HOME/code/libelium-dbt-training"
./discard-lab-workspace.sh "$LAB_DIR"

LAB_DIR="$(./new-lab-workspace.sh your-name --path-only)"
cd "$LAB_DIR"
uv sync --frozen
uv run dbt seed --profiles-dir . --full-refresh
uv run dbt build --profiles-dir . --select +fct_orders+
```

Do not use `rm -rf` manually. The discard helper validates both the temporary
path pattern and the marker created by `new-lab-workspace.sh`.
