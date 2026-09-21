#!/bin/bash

set -euo pipefail
cd "$(dirname "$0")/../.."
python3 scripts/tests/web-forward.py
python3 scripts/tests/epics-env.py
