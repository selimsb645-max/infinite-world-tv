#!/usr/bin/env bash
# INFINITE WORLD TV — Phase 05.1 asset integration test runner.
# Runs the headless logic suite (factory wiring, animation states,
# world/obstacle/collectible integration, autopilot, generation,
# the primitive-fallback GUARD, dashboard bridge accuracy), then
# the Xvfb visual QA twice: Phase 02 primitive mode
# (IWT_FACTORY_VISUALS=0, the "before" numbers) and factory mode
# (the integrated game, whose screenshots remain on disk as the
# evidence set). Merged output: tests/asset_integration_output.txt
# ending with ASSET_INTEGRATION_DONE failures=N.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.3-stable_linux.x86_64}"
OUT="tests/asset_integration_output.txt"
TMP="$(mktemp -d)"

"$GODOT" --headless --path game res://tests/AssetIntegrationTest.tscn \
  > "$TMP/logic.txt" 2>&1
grep -E "^(PASS|FAIL|MEASURED|ASSET_INTEGRATION_LOGIC_DONE)" "$TMP/logic.txt" > "$TMP/logic_clean.txt" || true

IWT_FACTORY_VISUALS=0 xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path game res://tests/VisualQaTest.tscn \
  > "$TMP/qa_prim.txt" 2>&1
grep -E "^(PASS|FAIL|MEASURED|VISUAL_QA_DONE)" "$TMP/qa_prim.txt" > "$TMP/qa_prim_clean.txt" || true

xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path game res://tests/VisualQaTest.tscn \
  > "$TMP/qa.txt" 2>&1
grep -E "^(PASS|FAIL|MEASURED|VISUAL_QA_DONE)" "$TMP/qa.txt" > "$TMP/qa_clean.txt" || true

{
  echo "== Phase 05.1 asset integration — logic suite (headless) =="
  cat "$TMP/logic_clean.txt"
  echo "== Phase 05.1 visual QA — primitive mode (before) =="
  cat "$TMP/qa_prim_clean.txt"
  echo "== Phase 05.1 visual QA — factory mode (integrated) =="
  cat "$TMP/qa_clean.txt"
} > "$OUT"

fails="$(grep -c '^FAIL' "$OUT" || true)"
for marker in ASSET_INTEGRATION_LOGIC_DONE VISUAL_QA_DONE; do
  if ! grep -q "$marker" "$OUT"; then
    echo "FAIL: missing_marker_$marker" >> "$OUT"
    fails=$((fails + 1))
  fi
done
echo "ASSET_INTEGRATION_DONE failures=$fails" >> "$OUT"
cat "$OUT"
rm -rf "$TMP"
exit "$fails"
