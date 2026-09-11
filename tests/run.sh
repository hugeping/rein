#!/bin/sh
# Run the headless Lua tests from the repo root.
set -e
cd "$(dirname "$0")/.."
exec luajit tests/run.lua tests/*_test.lua "$@"
