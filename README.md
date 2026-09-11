# Libelium dbt training

Self-contained learner repository for the dbt Foundations workshop. It uses
fictional e-commerce data, dbt Core, `dbt-duckdb`, DuckDB and DuckDB UI. No
cloud project or credentials are required.

## 1. Get the repository locally

The repository is private. Ask the instructor for GitHub access before the
session.

Check that Git is available:

```bash
git --version
```

Clone the repository into a predictable location:

```bash
mkdir -p "$HOME/code"
cd "$HOME/code"
git clone https://github.com/carleondel/libelium-dbt-training.git
cd libelium-dbt-training
pwd
```

If your organization uses the GitHub CLI, the equivalent authenticated clone
is:

```bash
mkdir -p "$HOME/code"
cd "$HOME/code"
gh auth login
gh repo clone carleondel/libelium-dbt-training
cd libelium-dbt-training
pwd
```

Run every remaining command in a Bash-compatible shell. On Windows, use WSL.

## 2. Install uv

Check whether `uv` is already installed:

```bash
uv --version
```

If it is missing on macOS or Linux:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
exec "$SHELL" -l
uv --version
```

If it is missing inside WSL, use the same Linux commands from the WSL shell.

## 3. Create your disposable learner workspace

Do not edit `starter/`. It is the clean reusable project. Create a temporary
copy and work there:

```bash
cd "$HOME/code/libelium-dbt-training"
REPO_DIR="$(pwd)"
LAB_DIR="$(./new-lab-workspace.sh learner --path-only)"
cd "$LAB_DIR"
pwd
```

`LAB_DIR` now contains the exact path of your isolated copy. Keep this terminal
open so the variable remains available.

## 4. Create the environment and prove the starter works

Run the complete block:

```bash
uv sync --frozen
uv run dbt --version
uv run python -c "import duckdb; print(duckdb.__version__)"
uv run dbt seed --profiles-dir . --full-refresh
uv run dbt ls --profiles-dir . --select +fct_orders+
uv run dbt build --profiles-dir . --select +fct_orders+
```

Optionally open the disposable copy in VS Code:

```bash
code .
```

Expected baseline:

- the seed step loads 15 customers, 18 orders and 18 payment snapshots;
- the build finishes with `PASS=20`;
- `fct_orders` contains 18 rows and 18 distinct `order_id` values.

Why the wrappers are deliberate:

- `uv sync --frozen` creates `.venv` and installs the exact versions in
  `uv.lock`;
- `uv run` uses this repository's environment instead of a global dbt or one
  belonging to another project;
- `--profiles-dir .` uses the included `profiles.yml`, which points dbt to the
  local file `target/sandbox.duckdb`;
- no manual `source .venv/bin/activate` step is required.

## 5. Inspect the local warehouse

After a build, launch DuckDB UI:

```bash
cd "$LAB_DIR"
uv run python scripts/start_duckdb_ui.py
```

Open `http://localhost:4213` if the browser does not open automatically. In
the UI, expand `sandbox` → `main`, preview `fct_orders`, or run:

```sql
select count(*) as row_count,
       count(distinct order_id) as distinct_orders
from fct_orders;
```

Return to the launcher terminal and press `Ctrl+C` before the next dbt build.
The UI keeps the DuckDB file open while it is running.

If the launcher reports `ModuleNotFoundError: No module named 'duckdb'`, run:

```bash
cd "$LAB_DIR"
uv sync --frozen
uv run python -c "import duckdb; print(duckdb.__version__)"
uv run python scripts/start_duckdb_ui.py
```

Do not fix this by activating an environment from another repository.

## 6. Complete the exercises

The guide and solutions were copied into your disposable workspace. Open the
learner guide with:

```bash
cd "$LAB_DIR"
code EXERCISE_GUIDE.md
```

You can also read the canonical
[starter/EXERCISE_GUIDE.md](starter/EXERCISE_GUIDE.md) on GitHub.

The workshop has two exercises:

1. **Micro-lab:** add `completed_order_amount` to `fct_orders`, rebuild it and
   verify that its one-row-per-order grain remains unchanged.
2. **Capstone:** deduplicate payment snapshots, aggregate payments to
   `order_id`, and add `paid_amount` to `fct_orders` without duplicating or
   removing orders.

The required capstone sequence is:

```text
raw payment snapshots
  → latest snapshot per payment_id
  → one payment summary per order_id
  → left join to fct_orders
  → build, test and inspect in DuckDB UI
```

If you are blocked, consult [starter/SOLUTIONS.md](starter/SOLUTIONS.md) one
section at a time. Using it as a hint is allowed. Creating `dim_customers` is
an optional stretch for early finishers, not a required task.

## 7. Start again from a clean copy

First stop DuckDB UI with `Ctrl+C`. If you are currently inside the lab, save
its path, return to the cloned repository and discard only that marked copy:

```bash
LAB_DIR="$(pwd)"
cd "$HOME/code/libelium-dbt-training"
./discard-lab-workspace.sh "$LAB_DIR"

LAB_DIR="$(./new-lab-workspace.sh learner --path-only)"
cd "$LAB_DIR"
uv sync --frozen
uv run dbt seed --profiles-dir . --full-refresh
uv run dbt build --profiles-dir . --select +fct_orders+
```

Optionally reopen the clean workspace with `code .`.

The discard helper refuses unmarked paths and refuses the repository's
`starter/` directory. Do not use `rm -rf` for the workshop reset.

## Repository layout

```text
libelium-dbt-training/
├── README.md
├── new-lab-workspace.sh
├── discard-lab-workspace.sh
└── starter/
    ├── EXERCISE_GUIDE.md
    ├── SOLUTIONS.md
    ├── dbt_project.yml
    ├── profiles.yml
    ├── pyproject.toml
    ├── uv.lock
    ├── seeds/
    ├── models/
    ├── tests/
    └── scripts/start_duckdb_ui.py
```

All data is fictional. Do not add credentials, production identifiers,
customer data or company-specific metric definitions to this repository.
