# Phase 03 — Infinite Procedural Level Generator

Implemented 2026-11-24 on top of the Phase 02 engine. Everything runs
locally and deterministically from seeds — **no external AI API is
called for any level**. Phase 02 handcrafted levels, controls, UI and
the smoke test are unchanged and still pass (26/26).

## How a level is made

```
seed ─> DifficultyManager.profile_for(level_number, performance)
     ─> WorldGenerator.select_world(rng, history)     (8 worlds)
     ─> RouteGenerator.plan()                          (segment route)
     ─> SegmentGenerator.build_segment() per segment   (content)
     ─> LevelValidator.validate()                      (playability)
     ─> AntiRepetitionManager.evaluate() vs history    (freshness)
     └─ any rejection -> regenerate with derived seed (bounded:
        GenerationConfig.max_retries = 8) -> if all fail, a
        guaranteed-valid fallback template is served and counted.
```

The output is a level Dictionary in the same shape Phase 02's
`WorldManager.build()` already consumed, plus optional generated-only
keys (`ground_strips`, `path_strips`, `platforms`, `moving_platforms`,
`gates`, `rails`, `tunnel_arches`, `gaps`, `segments`, `theme_data`).
Generated levels therefore flow through the exact same build path as
handcrafted ones.

## Modules (all in `game/scripts/`)

| Module | Responsibility |
|---|---|
| `GenerationConfig` | All policy knobs: similarity threshold 0.80, max retries 8, history size 250, recent window 60, traversal limits derived from controller physics |
| `WorldGenerator` | Registry of 8 worlds (5 Phase 02 + Ocean World, Fantasy Islands, Futuristic Highway); picks the next world avoiding recent repeats; adding a world = 1 registry entry + 1 theme + 1 decor style |
| `EnvironmentGenerator` | Per-level theme variation: small seeded hue/saturation shift + fog scaling, so same-world levels don't look identical |
| `RouteGenerator` | Segment route: character/vehicle sections, features (run, platforms, slide_run, gap / slalom, gates, curve, bridge, tunnel), gentle lane offsets (≤2.2 m per segment), mode-transition pad placement |
| `SegmentGenerator` | Expands a segment: ground/path strips (gap segments omit ground and span it with a platform; bridge segments narrow the road and add rails), collectibles, platforms, moving platforms, gates, tunnel arches |
| `ObstacleGenerator` | Obstacle placement per segment honouring difficulty spacing and keeping the pad zone clear |
| `DifficultyManager` | Profile per level: obstacle count 2→5/segment, spacing 11→7 m, gap 3.0→4.4 m over 40 levels, then capped; optional ±0.05 performance nudge |
| `LevelValidator` | Independent re-check: spawn/finish safety, spacing, jump distance/height vs real physics (jump apex 1.74 m, distance 5.85 m theoretical; validated at 1.5 m / 5.0 m), vehicle corridor, road coverage/continuity, pad safety, collectible clearance, density vs difficulty |
| `LevelFingerprintManager` | Structural fingerprint (MD5 of canonical structure string) + token set for Jaccard similarity. Structure only — seed, theme and colours are excluded, so a recolored/reseeded copy still collides |
| `LevelHistoryManager` | Bounded history (250 entries, oldest evicted; fingerprint index for O(1) exact-duplicate checks) |
| `AntiRepetitionManager` | Rejects exact duplicates (vs full retained history) and near-duplicates (similarity ≥ 0.80 vs the last 60 levels) |
| `LevelGenerator` | Orchestrator + bounded retry + fallback + a budgeted generation queue (`enqueue`/`process_queue`) |
| `LevelTransitionManager` | Endless pipeline: holds current level + exactly one pregenerated next level |
| `ObjectPool` | Keyed node pool used by WorldManager for obstacle bodies and collectible areas (cap 48/key) |

## Game integration

- `GameManager.start_endless(seed)` enters endless mode; finishing a
  level advances the transition manager instead of cycling the
  handcrafted list. Restart reloads the current generated level.
  `start_game()` / `load_level_public()` leave endless mode.
- `WorldManager` builds the generated structures (strips, platforms,
  animated moving platforms on `AnimatableBody3D`, gates, rails,
  tunnel arches) and the three new decor styles (coral, mushrooms,
  pillars). Obstacles and collectibles are pooled and reused across
  builds (measured in tests: second generated build reused 11
  obstacle nodes).
- Memory bounds: history capped at 250 entries, transition manager
  retains ≤2 level definitions, pools capped per key, old level roots
  are freed on rebuild. RAM does not grow with session length by
  design; the test suite asserts the history/retention/pool bounds.

## Anti-repetition policy (explicit)

- Exact structural duplicates: rejected against the full retained
  history (250 levels).
- Structural near-duplicates: rejected at similarity ≥ 0.80 against
  the most recent 60 levels. After the window passes, a similar
  layout may legitimately recur — with a different world, route and
  environmental variation in practice.
- The 1,000-level verification run produced 1,000 distinct
  fingerprints, 0 fallbacks, 1,003 attempts (3 validation rejections
  regenerated) — see `tests/TESTING_REPORT_PHASE03.md`.

## Known limitations

- "Curve" vehicle segments are expressed as lane-offset shifts of the
  route (obstacles/collectibles/path strips follow the offset); the
  ground itself is still built from straight strips.
- Tunnels are arch frames over the road, not enclosed geometry.
- Validation is data-level (geometry/reachability math from the real
  controller constants), not a simulated playthrough of every level;
  the integration test does build and run generated levels in the
  real scene.
- Headless-only verification on this VM, same caveat as Phase 02:
  visuals/FPS on a real display were not measured here.
