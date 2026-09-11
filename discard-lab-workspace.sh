#!/usr/bin/env bash
set -euo pipefail

target_dir="${1:-}"

if [[ -z "${target_dir}" ]]; then
  printf 'Usage: %s /absolute/path/to/dbt-foundations-workspace\n' "$0" >&2
  exit 2
fi

if [[ "${target_dir}" != /* ]]; then
  printf 'Refusing relative path: %s\n' "${target_dir}" >&2
  exit 2
fi

case "${target_dir}" in
  /tmp/dbt-foundations-*|/private/tmp/dbt-foundations-*|/var/folders/*/dbt-foundations-*|/private/var/folders/*/dbt-foundations-*)
    ;;
  *)
    printf 'Refusing path outside the disposable lab pattern: %s\n' "${target_dir}" >&2
    exit 2
    ;;
esac

if [[ ! -f "${target_dir}/.dbt-training-disposable" ]]; then
  printf 'Refusing unmarked directory: %s\n' "${target_dir}" >&2
  exit 2
fi

if [[ ! -f "${target_dir}/dbt_project.yml" ]]; then
  printf 'Refusing directory without dbt_project.yml: %s\n' "${target_dir}" >&2
  exit 2
fi

rm -rf -- "${target_dir}"
printf 'Discarded disposable lab:\n%s\n' "${target_dir}"
