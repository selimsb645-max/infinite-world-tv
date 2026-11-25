#!/usr/bin/env bash
# INFINITE WORLD TV — streaming session launcher.
#
# Thin wrapper around scripts/stream_session.py (see that file for
# the full contract). Resolves the Godot binary the same way the
# rest of the project does (IWT_GODOT_BIN, then GODOT, then PATH)
# and hands every argument through:
#
#   bash scripts/run_stream_session.sh [--mode prepare_only|
#       private_test|live] [--duration-sec N] [--port N]
#       [--session-dir DIR]
#
# Mode and duration can also come from IWT_SESSION_MODE /
# IWT_SESSION_DURATION_SEC. The default mode is prepare_only,
# which removes the stream key from the environment before
# anything starts and therefore cannot stream anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_BIN="${IWT_GODOT_BIN:-${GODOT:-godot}}"
export IWT_GODOT_BIN="$GODOT_BIN"

exec python3 scripts/stream_session.py "$@"
