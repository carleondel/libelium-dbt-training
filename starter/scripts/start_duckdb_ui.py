from __future__ import annotations

import sys
from pathlib import Path

import duckdb


def main() -> int:
    project_dir = Path(__file__).resolve().parent.parent
    database_path = project_dir / "target" / "sandbox.duckdb"

    if not database_path.exists():
        print(
            "DuckDB file not found. Run dbt seed/build before opening the UI:\n"
            "  uv sync --frozen\n"
            "  uv run dbt seed --profiles-dir . --full-refresh\n"
            "  uv run dbt build --profiles-dir . --select +fct_orders+",
            file=sys.stderr,
        )
        return 1

    connection = duckdb.connect(str(database_path))
    try:
        connection.execute("SET ui_local_port = 4213")
        connection.execute("CALL start_ui()")
        print("\nDuckDB UI is available at http://localhost:4213")
        print("Keep this process running while you inspect the database.")
        print("Press Ctrl+C here before running another dbt build.\n")
        input("Press Enter to stop DuckDB UI... ")
    except KeyboardInterrupt:
        print("\nStopping DuckDB UI...")
    finally:
        try:
            connection.execute("CALL stop_ui_server()")
        except duckdb.Error:
            pass
        connection.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
