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

## Live streaming (Phase 07)

The streaming engine pushes the Phase 06 output to an RTMP(S)
ingest through a single monitored ffmpeg process. Credentials
come only from the environment (or a gitignored `.env` — copy
`.env.example`); they are never written to logs or status output.

```bash
export IWT_YOUTUBE_STREAM_KEY=...   # your key, from YouTube Studio
export IWT_ADMIN_TOKEN=...          # authorizes admin start/stop
```

```gdscript
var scfg := StreamConfig.new(EncodingConfig.preset_720p(30))
scfg.apply_environment()            # or load_env_file(".env")
var manager := StreamManager.new()
add_child(manager)
var admin := StreamAdmin.new(manager)
admin.prepare_stream({"frames_pattern": "recordings/frames/frame_%06d.png",
                      "audio_path": "recordings/mix.wav"}, scfg)
admin.start_stream(IWT_ADMIN_TOKEN) # public needs confirm flag too
admin.check_health()                # secret-free status snapshot
admin.stop_stream(IWT_ADMIN_TOKEN)
```

Verify (no YouTube contact — a local RTMP listener on 127.0.0.1
and a fake key):

```bash
GODOT=godot bash tests/run_stream_tests.sh
# Expected: STREAM_DONE failures=0 (51 checks) — see docs/PHASE07.md
# for the architecture, the secure setup, YouTube's current
# eligibility rules (operator must be 16+) and the honest
# free-infrastructure feasibility report.
```

## Admin dashboard (Phase 08)

A web dashboard over everything above — real status and controls,
nothing simulated. Localhost only by default.

```bash
export IWT_ADMIN_TOKEN=...          # login credential (SECRET)
export IWT_VIEWER_TOKEN=...         # optional read-only role
export IWT_GODOT_BIN=/path/to/godot # or `godot` on PATH
python3 dashboard/server.py         # http://127.0.0.1:8787
```

Sign in with a token; the dashboard can then start/stop the game
service, drive AI gameplay and rendering through the game bridge,
and operate streaming through the persistent stream service into
the real Phase 07 StreamAdmin (a public start still requires the
separate confirmation). With no stream key configured the
streaming section correctly reads NOT CONFIGURED. See
`docs/PHASE08.md` for the API, security model and limitations.

Verify:

```bash
GODOT=godot bash tests/run_dashboard_tests.sh
# Expected: DASHBOARD_DONE failures=0 (45 checks)
```

## Supervised long-run operation (Phase 09)

For anything beyond a manual session, run the stack under the
process supervisor. It owns the game, stream-service and
dashboard processes: unexpected exits are restarted with
exponential backoff (at most 5 restarts per 10 minutes per unit,
then the unit stays FAILED until an operator reset), each crash
preserves the unit's log tail under `crashes/` in the runtime
dir, and all dashboard-layer logs rotate at 5 MB × 3 files.

```bash
export IWT_GODOT_BIN=/path/to/godot # or `godot` on PATH
export IWT_ADMIN_TOKEN=<redacted>
export IWT_YOUTUBE_STREAM_KEY=<redacted>
python3 dashboard/supervisor.py                 # foreground
python3 dashboard/supervisor.py --status        # unit states
```

The supervisor shares pidfiles with the dashboard, so a service
started from the dashboard UI is adopted and supervised rather
than double-started. Stop it with SIGTERM/Ctrl-C for a graceful
shutdown of all units. On a real host, run the supervisor itself
under systemd (or equivalent) — it is otherwise a single point
of failure (see `docs/PHASE09.md` §2 #10 and §6 for the honest
infrastructure limits; no free tier guarantees 24/7 uptime).

Verify:

```bash
GODOT=godot bash tests/run_reliability_tests.sh
# Expected: RELIABILITY_DONE failures=0 (51 checks)
IWT_STABILITY_SEC=600 python3 tests/stability_run.py
# Expected: STABILITY_DONE failures=0 after a real 600 s run
```
