#!/usr/bin/env bash
# Phase 09 reliability test runner.
#
# Runs the GDScript fault/recovery suite (storage partial
# reclamation, windowed recovery budgets, bounded stream logging,
# AI perception faults, 1,000-level generation soak) and the
# Python supervisor fault-injection suite (kill/restart with
# backoff, crash-loop budget exhaustion, duplicate prevention,
# unit independence, log rotation), merges their output into
# tests/reliability_output.txt and appends the combined verdict:
#   RELIABILITY_DONE failures=N
#
# Usage:  GODOT=/path/to/godot bash tests/run_reliability_tests.sh
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="tests/reliability_output.txt"
TMP_LOGIC="$(mktemp)"
TMP_PY="$(mktemp)"

"$GODOT" --headless --path game res://tests/ReliabilityTest.tscn >"$TMP_LOGIC" 2>&1
LOGIC_FAIL="$(sed -n 's/.*RELIABILITY_LOGIC_DONE failures=\([0-9]*\).*/\1/p' "$TMP_LOGIC" | tail -1)"
LOGIC_FAIL="${LOGIC_FAIL:-999}"

python3 tests/reliability_test.py >"$TMP_PY" 2>&1
PY_FAIL="$(sed -n 's/.*RELIABILITY_PY_DONE failures=\([0-9]*\).*/\1/p' "$TMP_PY" | tail -1)"
PY_FAIL="${PY_FAIL:-999}"

{
	grep -E "^(PASS|FAIL|RELIABILITY_LOGIC|MEASURED)" "$TMP_LOGIC" || true
	grep -E "^(PASS|FAIL|RELIABILITY_PY)" "$TMP_PY" || true
	echo "RELIABILITY_DONE failures=$((LOGIC_FAIL + PY_FAIL))"
} > "$OUT"
rm -f "$TMP_LOGIC" "$TMP_PY"
echo "wrote $OUT — RELIABILITY_DONE failures=$((LOGIC_FAIL + PY_FAIL))"
exit $((LOGIC_FAIL + PY_FAIL > 0 ? 1 : 0))
