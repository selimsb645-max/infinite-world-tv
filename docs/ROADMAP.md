# Roadmap

Each phase ends with something runnable and testable. No phase starts before the previous
one's acceptance criteria pass in CI. Estimates assume one developer plus an AI agent.

## P0 — Planning (current)
Deliverables: this documentation set, repository skeleton, infrastructure decision.
Acceptance: architecture, infrastructure, risks and security documents reviewed and approved
by the owner; host choice recorded.

## P1 — Generation core, no graphics (~1 week)
Scope: `LevelGenerator`, `GameValidator`, `AntiRepetitionManager`, `generation_log.jsonl`.
No Godot scenes yet — layouts are plain data.
Acceptance (automated):
- 10,000 generated levels: 0 invalid spawns, 0 unreachable finishes.
- 0 fingerprint repeats inside any 500-level window.
- Similarity score p95 below threshold across the last 50.
- Determinism: same seed twice → byte-identical spec.
- Property test: for every gap in every level, gap ≤ computed jump arc.

## P2 — Gameplay skeleton in Godot (~1-2 weeks)
Scope: one runner scene, one vehicle scene, `CharacterController`, `VehicleController`,
`AutonomousPlayer`, `GameManager` mode switching. Placeholder primitives only.
Acceptance:
- Autonomous player completes 100 consecutive generated levels without human input.
- Every fall/stall recovers; session never ends.
- Headless test run in CI (no renderer) passes in under 5 minutes.

## P3 — Asset pipeline (~2 weeks)
Scope: `tools/blender_assets/` scripts for character, vehicle, 3 obstacle families, 3 themes;
`tools/audio_synth/` for music beds and SFX; provenance records.
Acceptance:
- CI fails if any asset lacks a provenance record.
- No asset derived from third-party IP (manual review checklist signed off).
- Asset load time under target; total build size documented.

## P4 — Render + encode pipeline (~1 week)
Scope: Godot `--write-movie` batch renderer, FFmpeg encoder, QC gates (black frame, silence,
frozen frame, loudness −14 LUFS).
Acceptance:
- A 12s segment renders deterministically on CI and matches the local render's frame hash.
- QC rejects a deliberately broken segment.
- Measured throughput (minutes of video per CPU-hour) recorded in INFRASTRUCTURE.md.

## P5 — Broadcast host (~1 week)
Scope: `stream_loop.py`, `health.py`, `recovery.py`, buffer pre-flight, reconnect backoff.
Acceptance:
- 24-hour soak: stream stays up; every induced disconnect reconnects within 60s.
- Buffer never runs dry with a 30-minute pre-flight check.
- Egress measured and documented.

## P6 — Dashboard (~1 week)
Scope: FastAPI app, auth (password + TOTP), RBAC, all status endpoints, controls, emergency
shutdown.
Acceptance:
- Every endpoint covered by a test; viewer role cannot mutate.
- Emergency shutdown verified to stop the streamer and alert.
- No secret is ever rendered into a page or log.

## P7 — Compliance and launch (~1 week)
Scope: "made for kids" audience setting, channel metadata, stream title/description rotation,
launch checklist, runbook.
Acceptance:
- YouTube channel live-enabled; first 24h stream monitored with logs attached.
- Child-safety review checklist completed (no violence, no gambling, no manipulative ads).
- Runbook covers: stream down, buffer empty, disk full, dashboard down, key rotation.

## Explicit non-goals for v1
- Learned (ML) autonomous player.
- Real-time in-game physics streaming.
- Multi-stream to Twitch/TikTok.
- Paid APIs of any kind.
