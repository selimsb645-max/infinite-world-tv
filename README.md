# INFINITE WORLD TV

An original, family-friendly 3D hybrid game — cartoon character running
and cartoon vehicle driving — designed to grow into an automated
YouTube Live gaming channel. All art is original primitive geometry
built in code; there are no external or paid assets.

## Status

- **Phase 01 — Architecture & infrastructure design:** done (blueprint approved by owner).
- **Phase 02 — Core Game Engine:** built and smoke-tested locally (this code).
  Godot 4.3 project with a playable character, a playable vehicle, smooth
  mode transitions, five environment themes, three handcrafted test
  levels, full menu/HUD/pause UI, and a 26-check headless smoke test —
  all passing (see `tests/TESTING_REPORT.md`).
- **Phase 03 — Infinite Procedural Level Generator:** built and tested
  locally. Seed-based generation across 8 worlds (3 new: Ocean, Fantasy
  Islands, Futuristic Highway), structural anti-repetition
  (fingerprints + similarity vs history), difficulty manager, level
  validator with bounded retries + fallback, object pooling and
  chunked transitions. 45-check generation suite passing, including a
  1,000-level run with 1,000 distinct fingerprints and 0 invalid
  levels (see `docs/PHASE03.md`, `tests/TESTING_REPORT_PHASE03.md`).
  Endless mode: `GameManager.start_endless(seed)`.
- **Phase 04 — Autonomous gameplay:** built and tested locally.
  AI autopilot controller (perception, decision engines, risk +
  route selection, bounded recovery, performance adaptation).
  Autopilot suite 29/29 passing, including 6/6 generated levels
  completed across 6 worlds (see `docs/PHASE04.md`,
  `tests/TESTING_REPORT_PHASE04.md`). Endless + autonomous mode:
  `GameManager.start_autonomous(seed)`.
- **Phase 05 — Original Asset & Visual Production Pipeline:** built
  and tested locally. 4 original characters (3 variants each),
  5 original vehicles, 10-state character animation + vehicle
  animation, 48 environment props across 8 worlds, 8 obstacles +
  5 collectibles with metadata, per-world materials/VFX, 20
  original synthesised audio clips (44.4 s), central asset
  registry + validation. Asset suite 237/237 passing (see
  `docs/PHASE05.md`, `tests/TESTING_REPORT_PHASE05.md`). All
  assets original — see `docs/ASSET_LICENSE.md`.
- **Phase 06 — Automated Video Production & Rendering Engine:**
  built and tested locally. Opt-in broadcast pipeline
  (`GameManager.setup_broadcast(cfg)`): viewport capture at
  configurable resolution/fps (1080p target, 720p fallback),
  FFmpeg H.264/AAC encoding to MP4, audio mixing from the Phase 05
  WAV library (music + world ambience + SFX events), broadcast
  overlays (world/level/score/mode/progress), timestamped recording
  segments with safe finalization, bounded storage with retention,
  health monitoring and bounded failure recovery. Video suite
  84/84 passing, including real encoded MP4s validated by ffprobe
  (see `docs/PHASE06.md`, `tests/TESTING_REPORT_PHASE06.md`).
  Measured honestly: this no-GPU VM renders ≈5 fps, so real-time
  high-fps capture is a hardware question, not a pipeline one.
- **Not yet built (later phases, need owner approval):** YouTube
  Live streaming (Phase 06 built and tested the RTMP command and
  its enable-gate only — no stream was started), admin dashboard,
  GitHub Actions session runtime (~6 h stream sessions with
  30–60 min breaks — not true 24/7).

## Run it

See [docs/RUNNING.md](docs/RUNNING.md). Short version: open `game/` in
Godot 4.x and press Play, or run headless tests:

```bash
godot --headless --path game --import
godot --headless --path game res://tests/SmokeTest.tscn
```

## Controls

| Action | Keys |
|---|---|
| Strafe / steer | A/D or ←/→ |
| Jump | Space / ↑ |
| Slide | S / ↓ |
| Accelerate / brake (vehicle) | W / S or ↑ / ↓ |
| Switch character ↔ vehicle | Tab / E (works anywhere; the car spawns at the runner) |
| Pause | Esc / P |

## Layout

- `game/` — the Godot project (`project.godot`, `scenes/`, `scripts/`, `tests/`)
- `docs/` — architecture and run instructions
- `tests/` — testing report and last smoke-test output
- `streaming/`, `dashboard/` — placeholders for later approved phases

Zero-cost rule: free and open-source tools only (Godot, Blender-compatible
pipeline, FFmpeg later). No paid services, no secrets in the repo.
