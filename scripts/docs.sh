#!/bin/bash
#
# Build the Sphinx documentation in docs/, or serve it with live reload.
#
#   scripts/docs.sh [serve|build] [extra sphinx args...]
#
# serve (the default) rebuilds on every save and serves the site at
# http://127.0.0.1:${PORT:-8000}. build runs the strict build that CI runs,
# with warnings as errors, and writes docs/_build/html. Both need uv.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

mode=${1:-serve}
shift || true

case $mode in
serve)
    exec uvx --with-requirements docs/requirements.txt --from sphinx-autobuild \
        sphinx-autobuild docs docs/_build/html --port "${PORT:-8000}" "$@"
    ;;
build)
    uv run --with-requirements docs/requirements.txt \
        sphinx-build -b html -W --keep-going docs docs/_build/html "$@"
    echo "Open $root/docs/_build/html/index.html"
    ;;
*)
    echo "usage: scripts/docs.sh [serve|build] [extra sphinx args...]" >&2
    exit 2
    ;;
esac
