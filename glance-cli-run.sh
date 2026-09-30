#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
venv_dir="$project_dir/.venv"

if [[ ! -x "$venv_dir/bin/python" ]]; then
  python3 -m venv "$venv_dir"
fi

"$venv_dir/bin/python" -m pip install --upgrade --force-reinstall -e "$project_dir/glance-cli"

if [[ $# -gt 0 ]]; then
  exec "$venv_dir/bin/glance" "$@"
fi

printf 'Glance CLI 已安装。需要启动 Worker 时，请运行：%s worker\n' "$venv_dir/bin/glance"
