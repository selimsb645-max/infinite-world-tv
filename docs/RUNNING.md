# Running INFINITE WORLD TV locally (Phase 02)

## Requirements

- Godot **4.x** (developed and tested against **4.3.stable** official).
  Free download: https://godotengine.org/download — or the GitHub
  releases of `godotengine/godot`. No other dependencies.

## Open and play

1. Launch Godot 4 and choose **Import**, then select this repo's
   `game/project.godot` (or from a terminal: `godot --path game`).
2. Press **Play** (F5). The main scene is `res://scenes/Main.tscn`.
3. In the main menu pick a start mode (Character/Vehicle) and a world
   theme, then press **PLAY**.

## Controls

| Action | Keys |
|---|---|
| Strafe / steer | A/D or ←/→ |
| Jump | Space / ↑ |
| Slide | S / ↓ |
| Accelerate / brake | W / S or ↑ / ↓ |
| Switch mode | Tab / E — the glowing pad in each level marks the car's home spot; switching works anywhere |
| Pause / resume | Esc / P, or the pause menu buttons |

## Headless verification (what CI / this VM runs)

```bash
# Import check — must complete with no script errors
godot --headless --path game --import

# Smoke test — drives the real game scene with real physics,
# prints PASS/FAIL per check, exits non-zero on any failure
godot --headless --path game res://tests/SmokeTest.tscn

# Phase 03 generation suite — 45 checks incl. a 1,000-level run
godot --headless --path game res://tests/GenerationTest.tscn
```

Expected: `SMOKE_DONE failures=0`, exit code 0. See
`tests/TESTING_REPORT.md` for the full results.

## Autonomous play (Phase 04)

The AI controller plays the game with no human input. From code:
`game.start_autonomous(777)` starts endless procedural play under
autopilot; `game.autonomous_controller.start_handcrafted()` plays the
handcrafted levels instead. Verify headlessly:

```bash
godot --headless --path game res://tests/AutopilotTest.tscn
# Expected: AUTOPILOT_DONE failures=0 — see docs/PHASE04.md and
# tests/TESTING_REPORT_PHASE04.md (real measured numbers).
```

Note: headless runs use
Godot's dummy rendering driver, which prints harmless
`mesh_get_surface_count / Parameter "m" is null` engine warnings; they
do not occur in a normal (windowed) run and are not game errors.

## Automated video production (Phase 06)

Recording is opt-in from code, mirroring autonomous play:

```gdscript
var cfg := EncodingConfig.preset_720p(30)   # or preset_1080p(30)
cfg.output_dir = "recordings"               # segment storage (capped)
var renderer = game.setup_broadcast(cfg)
renderer.start_continuous()                 # or start_recording() once
# ... later:
renderer.stop_continuous()
```

Each segment is encoded to MP4 (H.264 + AAC) with the Phase 05
audio mixed in, validated by ffprobe, and stored under
`cfg.output_dir` with the storage caps enforced. Verify:

```bash
# Logic suite (headless, 71 checks)
godot --headless --path game res://tests/VideoTest.tscn

# Capture suite — needs REAL pixels, so Xvfb instead of --headless
xvfb-run -a godot --path game res://tests/VideoCaptureTest.tscn

# Both, merged into tests/video_output.txt
GODOT=godot bash tests/run_video_tests.sh
# Expected: VIDEO_DONE failures=0 — see docs/PHASE06.md for the
# measured rates on this machine and the honest hardware limits.
```

YouTube Live / RTMP streaming is a later phase: Phase 06 only
builds and tests the RTMP command behind `EncodingConfig`'s
`rtmp_enabled` gate (default off).
