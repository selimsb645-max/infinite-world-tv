#!/usr/bin/env bash
# Phase 07 streaming test runner.
#
# Runs the headless stream suite (config/security/admin unit checks
# plus real ffmpeg streaming processes against a LOCAL RTMP listener
# on 127.0.0.1 — no YouTube connection, no real stream key) and
# writes the verdict into tests/stream_output.txt:
#   STREAM_DONE failures=N
#
# Usage:  GODOT=/path/to/godot bash tests/run_stream_tests.sh
# (GODOT defaults to `godot` from PATH; ffmpeg/ffprobe required.)
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="tests/stream_output.txt"
TMP_STREAM="$(mktemp)"

"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
"$GODOT" --headless --path game res://tests/StreamTest.tscn >"$TMP_STREAM" 2>&1
STREAM_FAIL="$(sed -n 's/.*STREAM_DONE failures=\([0-9]*\).*/\1/p' "$TMP_STREAM" | tail -1)"
STREAM_FAIL="${STREAM_FAIL:-999}"

{
	grep -E "^(PASS|FAIL|STREAM|MEASURED)" "$TMP_STREAM" || true
	echo "STREAM_DONE failures=${STREAM_FAIL}"
} > "$OUT"
rm -f "$TMP_STREAM"
echo "wrote $OUT — STREAM_DONE failures=${STREAM_FAIL}"
exit $((STREAM_FAIL > 0 ? 1 : 0))
