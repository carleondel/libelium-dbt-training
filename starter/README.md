# Generic e-commerce dbt sandbox

Small, reusable dbt project for the training exercises. The data is fictional
and intentionally compact. It uses an e-commerce shape similar to common dbt
tutorials without depending on any real business, repository, or customer data.

## Project shape

- `seeds/`: `raw_customers`, `raw_orders`, and `raw_payments` CSV fixtures.
- `models/staging/`: rename, cast and standardize the loaded sources.
- `models/intermediate/`: customer/order enrichment plus a deliberately
  unfinished payment model for the capstone.
- `models/marts/fct_orders.sql`: existing starter fact at one-row-per-order
  grain.
- `models/schema.yml`: base metadata and tests for the starter project.
- `tests/`: a singular test that should pass after payment deduplication.

The payment fixture contains repeated snapshots for some `payment_id` values,
and multiple payment attempts for some orders. That is intentional: learners
must keep the latest snapshot per payment key, aggregate to order grain, and
prove that the result has one row per order.

## Configure and run

The sandbox is local-first and uses DuckDB. The warehouse is a file at
`target/sandbox.duckdb`; no cloud account or credentials are required.
The first `uv sync` needs package-download access, and the first DuckDB UI
launch may need access to fetch its extension. After that, dbt and the data run
locally.

Do not solve exercises in the reusable master directory. From the repository
root, create a disposable learner workspace instead:

```bash
cd "$HOME/code/libelium-dbt-training"
LAB_DIR="$(./new-lab-workspace.sh your-name --path-only)"
cd "$LAB_DIR"
```

The command creates the copy, stores its exact path in `LAB_DIR`, and enters
it. Reset by closing DuckDB UI, discarding that temporary directory, and creating a new one. Keep a
second disposable copy for instructor solutions if you are facilitating the
training.

Check whether `uv` is available:

```bash
uv --version
```

If that command fails, install it first. On macOS/Linux:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
exec "$SHELL" -l
uv --version
```

On Windows PowerShell:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
uv --version
```

1. Create and fully populate the local environment from the committed
   `pyproject.toml` and `uv.lock`:

   ```bash
   uv sync --frozen
   uv run dbt --version
   uv run python -c "import duckdb; print(duckdb.__version__)"
   ```

   `uv sync --frozen` creates `.venv` when needed and installs the exact locked
   dependency set. Do not replace it with an empty `uv venv`. `uv run` then
   guarantees that dbt and Python come from this sandbox rather than another
   project or a global `PATH` entry. Activating the environment is not needed.

2. Run the commands from this directory (the included `profiles.yml` already
   points to DuckDB):

   ```bash
   uv run dbt seed --profiles-dir . --full-refresh
   ```

3. Inspect the starter graph and run the existing order fact with its parents:

   ```bash
   uv run dbt ls --profiles-dir . --select +fct_orders+
   uv run dbt build --profiles-dir . --select +fct_orders+
   ```

4. Inspect the local warehouse in DuckDB UI:

   ```bash
   uv run python scripts/start_duckdb_ui.py
   ```

   The browser opens at `http://localhost:4213`. Expand the `sandbox` catalog
   and `main` schema, select a relation, and use **Preview data** or a notebook
   query. Press `Ctrl+C` in the launcher terminal before running another dbt
   build; this closes the UI connection and avoids a database-file lock.

   The first UI launch may need internet access to install/load the DuckDB
   `ui` extension. Queries and data remain local. Signing in to MotherDuck is
   not required for this training. See the official
   [DuckDB UI documentation](https://duckdb.org/docs/lts/core_extensions/ui).

   If the launcher ever reports `ModuleNotFoundError: No module named
   'duckdb'`, do not activate another project's environment. From the current
   disposable workspace run exactly:

   ```bash
   uv sync --frozen
   uv run python -c "import duckdb; print(duckdb.__version__)"
   uv run python scripts/start_duckdb_ui.py
   ```

`profiles.yml.example` is kept as a copyable reference. For this sandbox it is
safe to use the local `profiles.yml` directly.

Every training command keeps `--profiles-dir .` deliberately. It tells dbt to
read the included local `profiles.yml` from the current project. Without it,
dbt normally searches the user's default profile location, which could select
another project or fail on a new learner machine.

## Micro-lab

The short exercise uses the existing `fct_orders` model. First inspect the
baseline in DuckDB UI. Then add `completed_order_amount`: it equals the order
amount for completed orders and zero otherwise. It is a deliberately simple
teaching metric for practising a `case` expression and observing a changed
warehouse relation; it is not presented as an official revenue definition.

1. Inspect `models/staging/stg_orders.sql`.
2. Add one readable column to `models/marts/fct_orders.sql`.
3. Run `uv run dbt parse --profiles-dir .`.
4. Run `uv run dbt build --profiles-dir . --select +fct_orders+`.
5. Open DuckDB UI, preview `fct_orders`, and state its grain.

## Star schema capstone

### Objective

Add `paid_amount` to the final `fct_orders` table without changing its
one-row-per-order grain. To do that safely, learners must:

1. keep the latest source snapshot for each `payment_id`;
2. aggregate the deduplicated payments to one row per `order_id`;
3. left join that order-level payment summary to `fct_orders`;
4. prove with tests and row counts that no orders were duplicated or lost.

The challenge is intentionally guided but technically substantial. If a
learner is blocked, they should use [`SOLUTIONS.md`](SOLUTIONS.md) one section
at a time rather than abandoning the exercise.

The capstone is intentionally scaffolded rather than greenfield:

1. **Extend the fact:** add `paid_amount` from the order-level payment summary
   to `fct_orders` while preserving one row per order.
2. **Resolve payment grain:** in `models/intermediate/int_order_payments.sql`,
   keep the latest row per `payment_id` with a rule such as `row_number()`,
   then aggregate the deduplicated rows to one row per `order_id`.
3. **Prove the grain:** add or preserve a singular test that fails when the
   intermediate payment result contains more than one row per order.
4. **Optional stretch for early finishers:** create `models/marts/dim_customers.sql` from
   `stg_customers`, document its grain, add a key test, and query by country or
   segment.

The expected final shape is:

```text
raw_customers   raw_orders   raw_payments
       ↓             ↓             ↓
stg_customers  stg_orders   stg_payments
       │             │             ↓
       └──── dim_customers   int_order_payments
                     \          /
                      fct_orders
```

The exact joins and business question are part of the challenge. Learners
should explain the grain before changing the SQL and should use schema YAML,
tests, and compiled results as evidence.

For a complete walkthrough with expected checks and copyable solutions, see
[`EXERCISE_GUIDE.md`](EXERCISE_GUIDE.md) and [`SOLUTIONS.md`](SOLUTIONS.md).

No credentials, production identifiers, real customer data, or client-specific
metric definitions belong in this folder.

## Start over safely

From the repository root, discard only a workspace created by the helper and
create a clean replacement:

```bash
cd "$HOME/code/libelium-dbt-training"
./discard-lab-workspace.sh "$LAB_DIR"
LAB_DIR="$(./new-lab-workspace.sh your-name --path-only)"
cd "$LAB_DIR"
uv sync --frozen
uv run dbt seed --profiles-dir . --full-refresh
uv run dbt build --profiles-dir . --select +fct_orders+
```

The discard helper refuses unmarked directories and paths outside the
temporary `dbt-foundations-*` workspace pattern. It cannot target the reusable
master.
