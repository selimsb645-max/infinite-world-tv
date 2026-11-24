# Phase 03 - Infinite Procedural Level Generation

Status: implemented and tested (2026-11-24). 38 generation checks + 37 Phase 02 regression
checks pass headless on Godot 4.3, locally and on GitHub Actions.

## What it does

The generator emits the exact Dictionary shape Phase 02 already consumed, so the controllers
never learn where a level came from:

```
seed -> world -> route -> obstacles -> validate -> anti-repeat -> accept
```

Anything that fails validation or looks like a recent level is discarded and regenerated with
a derived seed. After 8 attempts the generator returns a known-good fallback template, because
an infinite game must never stall.

## Modules

| Module | Responsibility |
|---|---|
| `generation_config.gd` | Every tunable and the physics constants the validator must agree with |
| `world_generator.gd` | The 8 worlds, their segment weights and obstacle palettes |
| `route_generator.gd` | Segment sequence; always opens and closes with a character run |
| `segment_generator.gd` | One segment: start z, length, mode, safe entry/exit |
| `obstacle_generator.gd` | Lane-aware placement inside a segment |
| `environment_generator.gd` | Per-visit variation: light, fog, decor density, palette shift |
| `level_fingerprint_manager.gd` | Exact fingerprint + structural signature + similarity |
| `level_history_manager.gd` | Bounded history (500), total counters |
| `anti_repetition_manager.gd` | Duplicate, recent-world and structural-clone checks |
| `difficulty_manager.gd` | The single 0.05-0.95 number everything reads |
| `level_validator.gd` | Re-derives playability from physics, refuses unfair levels |
| `level_transition_manager.gd` | Keeps only reachable segments, frees the rest |
| `level_generator.gd` | The orchestrator |

## Two decisions worth knowing

**Similarity is mean absolute difference, not cosine.** Measured on 1,770 pairs of different
levels, cosine sat at p50 0.916 and p90 0.9996, which flags unrelated levels as clones. MAD on
the same pairs gives p50 0.855, p90 0.908, p99 0.990, so the threshold 0.975 separates real
near-clones from merely similar levels. A recoloured clone still scores 1.000.

**Validation is independent of generation.** The validator recomputes jump reach, lane
occupancy and reaction gaps from `GenerationConfig` rather than trusting the generator. If a
new segment type is added later and it produces something unfair, validation rejects it instead
of the player discovering it.

## Measured results (this machine, Godot 4.3 headless)

| Check | Result |
|---|---|
| Levels generated | 1,000 in 236 ms (4,237 levels/s) |
| Passed validation | 1,000 / 1,000 |
| Both gameplay modes present | 1,000 / 1,000 |
| Unique fingerprints | 1,000 / 1,000 |
| Fallbacks needed | 0 |
| Rejections during the run | 678 (anti-repetition working as intended) |
| Worlds seen in 60 levels | 8 / 8, no consecutive repeats |
| Character lanes passable | 200 / 200 levels |
| Vehicle lanes passable | 200 / 200 levels |
| History window | capped at 500 after 700 generated |
| Segment eviction | 20 tracked -> 2 kept, 18 nodes freed |

## Known limitations

1. Obstacle count is modest (mean 3.1 per level). The budget scales with difficulty but the
   spacing rule dominates, so hard levels are long rather than dense.
2. "Moving platforms", "climbing sections" and "speed gates" exist as data (segment types and
   obstacle kinds) but the Phase 02 renderer draws all ground as one continuous slab. They
   become visible in Phase 04 when the world builder learns to draw per-segment geometry.
3. Memory is bounded by construction (history 500, segment window 3, level cache 12) but has
   only been measured in a 700-level loop, not in a multi-hour session.
