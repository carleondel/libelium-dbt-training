#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="${script_dir}/starter"
label="${1:-practice}"
output_mode="${2:-verbose}"
safe_label="$(printf '%s' "${label}" | tr -cd '[:alnum:]_-')"

if [[ -z "${safe_label}" ]]; then
  safe_label="practice"
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
lab_root="${TMPDIR:-/tmp}"
target_dir="${lab_root%/}/dbt-foundations-${safe_label}-${timestamp}"

mkdir -p "${target_dir}"
rsync -a \
  --exclude '.venv' \
  --exclude 'target' \
  --exclude 'logs' \
  --exclude 'dbt_internal_packages' \
  --exclude '.user.yml' \
  "${source_dir}/" "${target_dir}/"

touch "${target_dir}/.dbt-training-disposable"

if [[ "${output_mode}" == "--path-only" ]]; then
  printf '%s\n' "${target_dir}"
  exit 0
fi

printf 'Disposable lab created at:\n%s\n\n' "${target_dir}"
printf 'Next steps:\n'
printf '  cd %q\n' "${target_dir}"
printf '  uv sync --frozen\n'
printf '  uv run dbt seed --profiles-dir . --full-refresh\n'
printf '  uv run dbt build --profiles-dir . --select +fct_orders+\n\n'
printf 'Reset rule: discard this directory and run the helper again.\n'
printf 'The master sandbox was not modified.\n'
