# Architecture — Phase 02 module map

All gameplay code lives in `game/scripts/`, one responsibility per
module, created and wired together by the GameManager at runtime.
Scenes are intentionally thin (`scenes/Main.tscn` is just a root node
with the GameManager script) so everything is reproducible from code.

| Module | File | Responsibility |
|---|---|---|
| GameManager | `game_manager.gd` | Root orchestrator: game state (menu/playing/paused), score, level loading, mode transitions, restart, event routing |
| WorldManager | `world_manager.gd` | Builds/tears down level geometry (ground, decor, obstacles, collectibles, vehicle pad, finish zone); only the *active* body can trigger zones |
| LevelManager | `level_manager.gd` | Handcrafted test-level data (3 levels). The infinite generator is a later phase — not here |
| EnvironmentManager | `environment_manager.gd` | Five themes as data (sky, fog, sun, palette, decor style); applies WorldEnvironment + light live |
| CharacterController | `character_controller.gd` | `CharacterBody3D` runner from primitives: auto-run, strafe, jump, slide (collision shape shrinks), procedural bob/tilt animation |
| VehicleController | `vehicle_controller.gd` | `CharacterBody3D` arcade car from primitives: acceleration, braking/reverse, speed-sensitive steering, spinning wheels |
| CameraController | `camera_controller.gd` | One shared follow rig; mode-specific offsets, exponential smoothing, look-ahead — mode switches only change target + offset |
| InputManager | `input_manager.gd` | Single wrapper over the project Input actions, so tests/future autopilot can substitute input |
| CollisionManager | `collision_manager.gd` | Physics layer scheme (1 world, 2 player, 4 obstacle, 8 zones), groups, shared primitive/body builders, materials |
| AudioManager | `audio_manager.gd` | Original synthesized sine blips via `AudioStreamGenerator` (jump/collect/bump/switch); volume control; silent-safe with no audio device |
| UIManager | `ui_manager.gd` | Main menu (Play, mode + theme select, Settings: volume + low-quality toggle), HUD (score/level/mode/speed/hint), pause menu — all built in code |

## Phase 03 modules (procedural generation, `game/scripts/`)

Full design in `docs/PHASE03.md`. `LevelGenerator` orchestrates:
`DifficultyManager` → `WorldGenerator` (8 worlds, + `EnvironmentGenerator`
theme variation) → `RouteGenerator` → `SegmentGenerator` (+
`ObstacleGenerator`) → `LevelValidator` → `AntiRepetitionManager`
(`LevelFingerprintManager` + bounded `LevelHistoryManager`), with
bounded retries and a fallback template. `LevelTransitionManager`
feeds `GameManager.start_endless()` (current + one pregenerated
level); `ObjectPool` recycles obstacle/collectible nodes in
`WorldManager`. `GenerationConfig` holds every policy knob.

## Data flow

`LevelManager` (data) + `EnvironmentManager` (theme data) →
`WorldManager` builds geometry → `GameManager` places the controllers
and activates one → `CameraController` follows the active controller →
zone/collectible signals flow back through `WorldManager` →
`GameManager` (score, level completion) → `UIManager` reflects state.

## Phase 06 modules (video production, `game/scripts/`)

Full design in `docs/PHASE06.md`. Opt-in via
`GameManager.setup_broadcast(cfg)` → `VideoRenderer` orchestrates:
`GameCaptureManager` (viewport frames) → `AudioMixer` (Phase 05 WAV
layers) → `FFmpegManager` (H.264/AAC encode + ffprobe validation) →
`VideoSegmentManager` (partial → finalize) → `StorageManager`
(caps/retention), with `CaptureHealthMonitor` verdicts driving the
bounded `VideoRecoveryManager`. `CameraCaptureController` adds
broadcast framing over the Phase 02 rig (via its additive
`distance_scale`), `BroadcastOverlayManager` draws the overlay
graphics, and `EncodingConfig` holds every knob including the
disabled-by-default RTMP settings.

## Phase 07 modules (live streaming, `game/scripts/`)

Full design in `docs/PHASE07.md`. `StreamManager` (Node) owns one
ffmpeg RTMP(S) process fed from the Phase 06 output interface
(frame sequence + mixed WAV, or a file): prepare and broadcast are
separate calls, recovery is a bounded reconnect budget with
exponential backoff, and a pid-checked lock file prevents duplicate
encoders. `StreamConfig` carries the settings on top of
`EncodingConfig` and is the only place the stream key exists —
loaded from the environment / gitignored `.env`, used solely in
the process arguments, scrubbed from every string by `redact()`.
`StreamHealthMonitor` turns ffmpeg `-progress` reports into the
dashboard snapshot; `StreamAdmin` is the token-authorized control
surface (public start additionally needs an explicit confirmation
flag, default off).

## Phase 08 components (dashboard, `dashboard/` + `game/dashboard/`)

Full design in `docs/PHASE08.md`. A Python-stdlib backend
(`dashboard/server.py`) serves a static frontend and a JSON
API: token→session auth with admin/viewer roles, rate
limiting and an audit log; a status service aggregating
`/proc`, process liveness, recordings and two Godot bridge
snapshots; a process-control service over pidfiles; a log
service with redaction; an alert service. The bridges are
additive scenes — `GameService.tscn` (Main + status/command
bridge into GameManager / AutonomousController /
VideoRenderer) and `StreamService.tscn` (persistent owner
of the Phase 07 StreamManager/Admin pair). No Phase 02–07
file was modified for the dashboard.

## Phase 09 components (reliability, `dashboard/`)

Full design in `docs/PHASE09.md`. `dashboard/supervisor.py`
supervises the game, stream and dashboard processes
(zombie-aware liveness, shared pidfiles, crash-log
snapshots, exponential-backoff restarts with a bounded
window budget, per-unit independence) and
`dashboard/logrotate.py` bounds every dashboard-owned log.
In-engine hardening: windowed recovery budgets, bounded
append-only stream log, storage partial reclamation, AI
null-perception guards.

## Phase 10 (integration & deployment readiness)

No new runtime modules. Phase 10 added the end-to-end
integration suite (`game/tests/IntegrationTest.tscn`,
`tests/integration_test.py`, `tests/run_integration_tests.sh`)
that composes the phases above into one verified chain,
plus the final documentation set (`docs/PHASE10.md`,
`docs/DEPLOYMENT.md`, `docs/SECURITY.md`,
`docs/TROUBLESHOOTING.md`).

## Design constraints honoured

- Lightweight low-poly primitives only — the future runtime target is a
  no-GPU GitHub Actions runner at 720p, GL Compatibility renderer.
- No external assets, no paid services, no secrets anywhere in the repo.
- Family-friendly content only.
