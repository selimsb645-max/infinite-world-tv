#!/usr/bin/env bash
# Phase 08 dashboard test runner.
#
# Runs the Python dashboard suite (two real server instances over
# HTTP: auth/roles/rate-limit/health/audit/logs, then real game +
# stream control round-trips through the Phase 08 bridges into the
# actual Phase 04/06/07 modules) and writes the verdict into
# tests/dashboard_output.txt:
#   DASHBOARD_DONE failures=N
#
# Usage:  GODOT=/path/to/godot bash tests/run_dashboard_tests.sh
# (GODOT defaults to `godot` from PATH; ffmpeg required.)
set -u
cd "$(dirname "$0")/.."
export IWT_GODOT_BIN="${IWT_GODOT_BIN:-${GODOT:-godot}}"
OUT="tests/dashboard_output.txt"
TMP_DASH="$(mktemp)"

python3 tests/dashboard_test.py >"$TMP_DASH" 2>&1
DASH_FAIL="$(sed -n 's/.*DASHBOARD_DONE failures=\([0-9]*\).*/\1/p' "$TMP_DASH" | tail -1)"
DASH_FAIL="${DASH_FAIL:-999}"

{
	grep -E "^(PASS|FAIL|DASHBOARD|---)" "$TMP_DASH" || true
	echo "DASHBOARD_DONE failures=${DASH_FAIL}"
} > "$OUT"
rm -f "$TMP_DASH"
echo "wrote $OUT — DASHBOARD_DONE failures=${DASH_FAIL}"
exit $((DASH_FAIL > 0 ? 1 : 0))
