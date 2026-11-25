#!/usr/bin/env bash
# Phase 10 end-to-end integration runner.
#
# Leg 1 (GDScript, Xvfb): the in-engine chain — boot, Phase 05
# assets/audio, generated level + autonomous character/vehicle
# gameplay, Phase 06 capture/render (ffprobe-validated), capture
# health, Phase 07 stream PREPARE against a local ingest only.
# Leg 2 (Python): the production topology — Phase 09 supervisor
# owning game/stream/dashboard, dashboard auth + real status,
# dashboard-driven autonomous start, SIGKILL fault injection and
# supervisor recovery.
#
# A FAKE stream key and a dead local ingest (127.0.0.1:19359) are
# exported for leg 1 only; prepare spawns nothing and no packet
# leaves this machine. No YouTube endpoint is contacted.
#
# Writes tests/integration_output.txt with the combined verdict:
#   INTEGRATION_DONE failures=N
#
# Usage:  GODOT=/path/to/godot bash tests/run_integration_tests.sh
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="tests/integration_output.txt"
TMP_CHAIN="$(mktemp)"
TMP_SYSTEM="$(mktemp)"

IWT_YOUTUBE_STREAM_KEY="IWT-E2E-FAKE-KEY" \
IWT_RTMP_INGEST_URL="rtmp://127.0.0.1:19359/live" \
IWT_STREAM_VISIBILITY="private" \
IWT_ADMIN_TOKEN="integration-admin-token" \
	xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path game \
	--resolution 1280x720 res://tests/IntegrationTest.tscn \
	>"$TMP_CHAIN" 2>&1
CHAIN_FAIL="$(sed -n 's/.*INTEGRATION_CHAIN_DONE failures=\([0-9]*\).*/\1/p' "$TMP_CHAIN" | tail -1)"
CHAIN_FAIL="${CHAIN_FAIL:-999}"

IWT_GODOT_BIN="$GODOT" python3 tests/integration_test.py >"$TMP_SYSTEM" 2>&1
SYSTEM_FAIL="$(sed -n 's/.*INTEGRATION_SYSTEM_DONE failures=\([0-9]*\).*/\1/p' "$TMP_SYSTEM" | tail -1)"
SYSTEM_FAIL="${SYSTEM_FAIL:-999}"

{
	grep -E "^(PASS|FAIL|INTEGRATION_CHAIN|MEASURED)" "$TMP_CHAIN" || true
	grep -E "^(PASS|FAIL|INTEGRATION_SYSTEM|MEASURED)" "$TMP_SYSTEM" || true
	echo "INTEGRATION_DONE failures=$((CHAIN_FAIL + SYSTEM_FAIL))"
} > "$OUT"
rm -f "$TMP_CHAIN" "$TMP_SYSTEM"
echo "wrote $OUT — INTEGRATION_DONE failures=$((CHAIN_FAIL + SYSTEM_FAIL))"
exit $((CHAIN_FAIL + SYSTEM_FAIL > 0 ? 1 : 0))
