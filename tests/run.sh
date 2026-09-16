#!/bin/sh
# Run the headless tests from the repo root.
set -e
cd "$(dirname "$0")/.."
# C tests for src/tls
cc -O2 -Wall -I src/tls tests/tls_test.c \
	src/tls/i31.c src/tls/ec.c src/tls/ecdsa.c src/tls/rsa.c \
	-o tests/tls_test
tests/tls_test
luajit tests/run.lua tests/*_test.lua "$@"
