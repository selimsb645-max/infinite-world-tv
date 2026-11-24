#!/usr/bin/env bash
# Phase 06 video-production test runner.
#
# Runs the headless logic suite and the Xvfb real-pixel capture
# suite, merges their output into tests/video_output.txt and appends
# the combined verdict line:  VIDEO_DONE failures=N
#
# Usage:  GODOT=/path/to/godot bash tests/run_video_tests.sh
# (GODOT defaults to `godot` from PATH; Xvfb must be installed for
# the capture half — without real pixels it cannot pass.)
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="tests/video_output.txt"
TMP_LOGIC="$(mktemp)"
TMP_CAPTURE="$(mktemp)"

"$GODOT" --headless --path game res://tests/VideoTest.tscn >"$TMP_LOGIC" 2>&1
LOGIC_FAIL="$(sed -n 's/.*VIDEO_LOGIC_DONE failures=\([0-9]*\).*/\1/p' "$TMP_LOGIC" | tail -1)"
LOGIC_FAIL="${LOGIC_FAIL:-999}"

xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path game \
	--resolution 1280x720 res://tests/VideoCaptureTest.tscn >"$TMP_CAPTURE" 2>&1
CAPTURE_FAIL="$(sed -n 's/.*VIDEO_CAPTURE_DONE failures=\([0-9]*\).*/\1/p' "$TMP_CAPTURE" | tail -1)"
CAPTURE_FAIL="${CAPTURE_FAIL:-999}"

{
	grep -E "^(PASS|FAIL|VIDEO_LOGIC|MEASURED)" "$TMP_LOGIC" || true
	grep -E "^(PASS|FAIL|VIDEO_CAPTURE|MEASURED)" "$TMP_CAPTURE" || true
	echo "VIDEO_DONE failures=$((LOGIC_FAIL + CAPTURE_FAIL))"
} > "$OUT"
rm -f "$TMP_LOGIC" "$TMP_CAPTURE"
echo "wrote $OUT — VIDEO_DONE failures=$((LOGIC_FAIL + CAPTURE_FAIL))"
exit $((LOGIC_FAIL + CAPTURE_FAIL > 0 ? 1 : 0))
