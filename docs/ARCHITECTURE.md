# Architecture

## 1. The constraint that shapes everything

The specification asks for a game that "operates continuously" and a stream that runs 24/7.
Those are two different problems and they must not share a process.

**Rendering is expensive and bursty. Streaming is cheap and constant.**

- Godot at 1080p on a software renderer (any free cloud VM) runs at a few FPS. Unusable for
  real-time capture.
- GitHub Actions cannot hold a job open for a month, and its runners have no GPU.
- A 1080p60 H.264 stream at 4.5 Mbps needs ~48 GB/day of egress. Most free tiers either cap
  egress or forbid continuous streaming outright.

So the system renders **ahead** into a segment queue and the always-on process only loops
segments into RTMP. This is how every 24/7 "lofi" channel on YouTube actually works, and it
is the only design that fits a zero-cost budget.

```
                 ┌──────────────── render side (bursty, no uptime requirement) ───────────┐
 seed + rules ─► │ LevelGenerator ─► GameValidator ─► Godot --write-movie ─► frames/     │
                 │        │              │                                    │          │
                 │   fingerprint     reject+regen                        FFmpeg encode   │
                 └────────┼──────────────┼────────────────────────────────────┼──────────┘
                          │              │                                    ▼
                    anti-repetition   quarantine                    segments/NNNN.mp4 (12s)
                          │                                                 │
                 ┌────────▼────────── stream side (always on, <1 core) ─────▼──────────┐
                 │ segment queue ─► stream_loop.py ─► FFmpeg ─► YouTube RTMP            │
                 │        ▲                    │                                        │
                 │   health.py ◄───────────────┘  (bitrate, drops, reconnect, restart)  │
                 └──────────────────────────────────────────────────────────────────────┘
```

## 2. Why Godot Movie Maker mode, not screen capture

Godot 4 can run a scene and write every frame to disk at a fixed timestep
(`--write-movie`), independent of how fast the machine renders. That gives:

- deterministic output for a given seed (a level can be re-rendered identically),
- no dropped frames when the host is slow,
- no dependency on a GPU or a display server,
- testability: the same seed in CI and on a laptop produces the same frames.

This is the single most important technical choice in the project. Real-time capture would
make every later requirement (recovery, QC, reproducibility) far harder.

## 3. Module boundaries

Gameplay logic is pure GDScript with no rendering assumptions, so it can run headless in
tests.

| Module | Responsibility | Must not do |
|---|---|---|
| `GameManager` | session lifecycle, mode switching (runner ↔ racer), score, restart | generate geometry |
| `WorldManager` | load/unload a generated level, theme application, lighting rig | decide difficulty |
| `LevelGenerator` | seed → layout spec (pure data, no nodes) | instantiate meshes |
| `AntiRepetitionManager` | fingerprints, similarity scoring, rejection rules | own the seed |
| `GameValidator` | reachability, spawn/finish validity, playability | fix levels (it only rejects) |
| `DifficultyManager` | curve from distance/score, feeds generator constraints | touch the player |
| `AssetManager` | asset registry, provenance, instancing | download anything at runtime |
| `CharacterController` | runner physics: run, jump, slide, stumble recovery | decide the route |
| `VehicleController` | racer physics: steering, boost, lane logic | decide the route |
| `AutonomousPlayer` | perception (raycasts) → decisions → inputs | bypass physics |
| `AudioManager` | music bed, SFX, ducking, loudness target | fetch remote audio |

The split that matters: **LevelGenerator returns data, not scenes.** A layout is a plain
dictionary that can be validated, hashed, diffed and unit-tested without starting Godot's
renderer. `WorldManager` turns that data into nodes.

## 4. Procedural generation

### 4.1 Level spec (pure data)

```json
{
  "seed": 84213907,
  "theme": "canyon_dawn",
  "length_m": 900,
  "segments": [
    {"kind": "platform_run", "obstacles": ["crate_low", "beam_high"], "gap_m": 3.2},
    {"kind": "vehicle_section", "lane_pattern": "weave", "traffic": 6}
  ],
  "difficulty": 0.42,
  "spawn": {"x": 0, "y": 0, "z": 0},
  "finish": {"x": 0, "y": 12, "z": 900}
}
```

### 4.2 Pipeline

1. `seed` → PRNG (PCG64) → segment grammar expansion with difficulty-weighted rules.
2. Grammar produces segments from a **closed catalogue** of authored segment types. Randomness
   picks and parameterises; it never invents geometry at runtime.
3. `GameValidator` checks:
   - spawn is on solid ground with 2 m clearance,
   - every gap is within the character's jump arc at the current speed (computed, not guessed),
   - the route from spawn to finish is traversable (graph search over segment connection points),
   - vehicle sections have a legal entry and exit,
   - finish trigger exists and is reachable.
4. Invalid → regenerate with `seed+1` up to N attempts, then fall back to a known-good layout
   and log the failure. **Never ship an unvalidated level.**

### 4.3 Anti-repetition

- `fingerprint = sha256(canonical_json(spec_without_seed))[:16]`
- Hard rule: a fingerprint may not repeat within the last 500 levels.
- Soft rule: cosine distance over a feature vector
  `[length, mean_gap, obstacle_mix, vehicle_ratio, theme_id, difficulty]` must exceed a
  threshold against the last 50 levels; otherwise regenerate.
- Every generated level is appended to `generation_log.jsonl` (seed, fingerprint, features,
  accepted/rejected, reason) — this is the audit trail the spec asks for.

## 5. Autonomous player

Deterministic policy, not a neural net, for the first version:

- **Perception:** forward raycasts at 3 heights + ground probe, sampled every physics tick.
- **Policy:** state machine — `RUN → JUMP → SLIDE → LAND → RUN`, plus `VEHICLE_STEER`.
  Decision thresholds derive from current speed and the next obstacle's distance.
- **Safety:** if the character falls or stalls, `AutonomousPlayer` triggers a recovery
  (respawn at last safe checkpoint) and logs it. A recoverable failure must never end the
  session; the stream must not go black.
- Because it is deterministic and seed-driven, the same level always produces the same run —
  which is what makes pre-rendering valid.

A learned policy is explicitly out of scope for v1. It would make runs non-reproducible and
add a paid training dependency, which the spec forbids.

## 6. Asset pipeline and originality

Every asset must be produced by a script in `tools/blender_assets/` or
`tools/audio_synth/`, and each must carry a provenance record:

```json
{"id": "char_runner_01", "source": "procedural", "script": "tools/blender_assets/runner.py",
 "author": "this repository", "license": "original", "created": "2026-11-24", "hash": "..."}
```

Rules:
- No asset may enter `game/assets/` without a provenance record; CI fails the build if one is
  missing.
- Textures: only generated noise/gradients or explicitly CC0 sources, recorded with URL and
  license.
- Audio: synthesised in-repo (oscillator/noise + envelopes) so Content ID cannot match it.
- No logos, no brand names, no recognisable third-party characters or vehicles.

## 7. Broadcast layer

`broadcast/stream_loop.py`:

- reads `segments/` in order, loops forever, never runs dry (pre-flight check requires ≥ 30
  minutes of buffer),
- pipes to FFmpeg with `-re` (real-time pacing) → RTMP,
- watches FFmpeg's stderr for frame drops, bitrate, and disconnect keywords,
- on disconnect: exponential backoff reconnect (5s → 10s → 30s → 60s, cap), max 10 attempts,
  then controlled restart of the process and a dashboard alert,
- writes `broadcast_health.json` every 5s (uptime, kbps, fps, drops, last error).

`broadcast/recovery.py` supervises: if the streamer exits non-zero twice within 10 minutes,
it re-renders the next segment first (so the queue is never empty) before restarting.

## 8. Dashboard

FastAPI + server-rendered pages (no JS framework, so it works from a phone browser):

- Auth: password + TOTP, HMAC-signed session cookie, role-based (`admin`, `viewer`).
- Read-only views for status; mutating endpoints require `admin` and a CSRF token.
- Endpoints mirror the spec: overview, world/level, counters, gameplay status, stream status,
  CPU/memory, FPS/bitrate, logs, start/stop/restart, config, emergency shutdown.
- Emergency shutdown kills the streamer and stops the render loop, then posts a "stream
  stopped by admin" message to the alert channel.
