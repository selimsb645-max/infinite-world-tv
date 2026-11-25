# Phase 05 — Original Asset & Visual Production Pipeline

Status: **built and tested locally** (2026-11-24). Asset suite **237/237 PASS**
(`tests/asset_output.txt`). Regressions clean: Phase 02 smoke 26/26,
Phase 03 generation 45/45, Phase 04 autopilot 29/29.

## What changed vs the audit

The audit found visuals scattered as primitives in code, no asset
folder, no registry, no animation system, and audio only as sine-tone
blips. Phase 05 fixes exactly that — without touching gameplay,
generation or the autopilot (all three regressions pass unchanged).

## What was built

| Area | Files | Contents |
|---|---|---|
| Characters | `game/scripts/character_factory.gd` | 4 original characters (Pip, Zara, Milo, Nova), distinct silhouettes/heights, own accessory each, 3 colour variants each, modular parts (Body/Head/Accessory/Arms/Legs) |
| Vehicles | `game/scripts/vehicle_factory.gd` | 5 original vehicles (SportsCar, OffRoad, Futuristic, Compact, Fantasy), steering front axle, 4 wheel pivots each, collision spec |
| Character animation | `game/scripts/character_animation.gd` | 10-state machine (idle/run/sprint/jump/fall/land/slide/climb/celebrate/recover), validated transitions, bob/lean/crouch posing |
| Vehicle animation | `game/scripts/vehicle_animation.gd` | Wheel spin from speed, front steering, suspension bob, brake dive / accel squat, collision shake |
| Environment assets | `game/scripts/environment_assets.gd` | 48 props across all 8 worlds (6 per world); solid kinds (platform/bridge/tunnel) are real StaticBody3D |
| Obstacles & collectibles | `game/scripts/obstacle_collectible_library.gd` | 8 obstacles (moving platform, rotating barrier, jump gate, sliding barrier, falling platform, road barrier, moving vehicle, hazard) + 5 collectibles (coin, star, energy, score bonus, power-up), all with collision + gameplay metadata |
| Materials & VFX | `game/scripts/material_library.gd` | Per-world palette + lighting preset (from the world theme), 6 one-shot particle effects |
| Audio | `game/scripts/audio_library.gd` + `tools/generate_audio.py` + `game/assets/audio/*.wav` | 20 original synthesised WAV clips (44.4 s total): 12 one-shots, engine + music loops, 8 per-world ambiences. No external audio. |
| Registry | `game/scripts/asset_registry.gd` | Central registry + `validate()` (builds one of everything, reports gaps) + `summary()` counts |

## Tests

- `game/tests/AssetTest.tscn` / `asset_test.gd` — 237 checks, all
  passing, including a full registry validation (builds every asset).
- Run: `godot --headless --path game res://tests/AssetTest.tscn`
- Generate audio again: `python3 tools/generate_audio.py`
  (then `godot --headless --path game --import` to re-import WAVs).

## Honest limits

- Characters/vehicles are still primitive-geometry builds in code
  (the spec's Blender pipeline is documented as Blender-compatible
  specs, but no Blender binary exists on this VM, so no .blend files
  were produced).
- **Update (Phase 05.1, 2026-11-25):** the factories are now wired
  into the live game — the live character/vehicle/world are the
  factory/library builds, driven by the real controllers, with a
  Phase 02 primitive fallback kept for comparison. See
  `docs/PHASE05_1.md` for the root-cause analysis and the wiring.
  The geometry itself remains code-built primitives, as above.
- Audio is original synthesis, not recorded music — music/ambience
  are simple pads, not composed tracks.
- Animation is procedural posing (bob/lean/crouch), not baked
  keyframe clips; there is no AnimationPlayer timeline yet.
- The new factories are a library: the live controllers still use
  their Phase 02 visuals. Wiring CharacterFactory/VehicleFactory
  into the controllers is the next integration step, not done here,
  so gameplay is preserved exactly as the spec required.
- Headless only; no real-display visual check was possible.

## Licensing

All assets are original — see `docs/ASSET_LICENSE.md`. No external
assets, no trademarks, no copied characters or vehicles.
