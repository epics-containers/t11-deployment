#!/bin/bash
set -euo pipefail

if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.local/bin:${PATH}"
fi

uv run --script scripts/check_apps_values.py apps/values.yaml

cd "$(dirname "$0")/../.."
python3 scripts/tests/web-forward.py
python3 scripts/tests/epics-env.py
bash scripts/tests/smoke-test-context.sh
