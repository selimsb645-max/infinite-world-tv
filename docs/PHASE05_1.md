# Phase 05.1 — Asset Integration, Visual QA & Gameplay Repair

Status: COMPLETE (local). This phase wires the Phase 05 asset
factories into the live gameplay scene. It is a focused repair:
the Phase 02 physics controllers stay authoritative, factory
visuals attach to them and follow their transforms, and Phases
02–10 behaviour (movement, collision, AI perception, generation,
capture, streaming, dashboard) is preserved. No GitHub push is
part of this phase; the parent verifies and pushes.

## 1. Root-cause analysis (audited from code)

Phase 05 delivered its factories as a **library plus registry**,
validated only by `game/tests/asset_test.gd`
(`AssetRegistry.validate()` builds every asset in isolation).
No production code ever called them:

- The live boot path is `game/scenes/Main.tscn` → `GameManager`
  (`game/scripts/game_manager.gd`), which creates
  `CharacterController` and `VehicleController` in `_ready()`.
  Each controller's `_build_visual()` hard-built Phase 02
  primitives via `CollisionManager.make_material` (capsule+sphere
  character; box+cabin+wheels vehicle).
- `WorldManager` (`game/scripts/world_manager.gd`) built its own
  Phase 02/03-style objects in `_make_decor()`, `_make_obstacle()`
  and `_make_collectible()` (via `CollisionManager.make_static_box`
  / `make_collectible`).
- `CharacterFactory`, `VehicleFactory`,
  `EnvironmentAssetLibrary`, `ObstacleCollectibleLibrary`,
  `CharacterAnimation`, `VehicleAnimation` and
  `MaterialLibrary.palette()` were referenced **only** by the
  asset test and the registry validator — never by the scene the
  player (and the Phase 06 camera) actually sees.

Phase 05's own docs recorded this as a deferred step ("factories
not wired into the live controller"), and Phase 10 repeated it as
future feature work. The result: every Phase 05 asset validated
in isolation while the live game kept rendering the Phase 02
primitive world. This phase closes exactly that gap.

## 2. What was integrated, per area

Integration pattern: controllers keep their physics, input and AI
interfaces byte-for-byte in behaviour; the factory node replaces
only the visual child. A Phase 02 primitive fallback remains
available (`IWT_FACTORY_VISUALS=0` env or
`GameManager.set_factory_visuals_enabled(false)`) for comparison
and as the guard test's forced-fallback toggle.

### Character — INTEGRATED
- `CharacterController._build_visual()` now builds
  `CharacterFactory.build(character_name, character_variant)`
  (default Pip variant 0) under the existing visual node; the
  factory root follows the body transform exactly (it is a child
  of the controller, as the primitive visual was).
- Selection: `set_character(name, variant)` (rejects unknown
  names, keeps the current model), env overrides
  `IWT_CHARACTER` / `IWT_CHARACTER_VARIANT` applied by
  `GameManager._ready()`.
- `CharacterAnimation` (RefCounted state machine, created with
  the factory visual) is driven by **real gameplay states** in
  `_drive_animation()`: idle/run from speed, jump on upward
  velocity, fall on descent, land on touchdown, slide while
  sliding, recover for 0.45 s after an obstacle bump (the
  existing `bumped_obstacle` path), celebrate for 0.9 s from
  `GameManager._on_finish_reached()` via `character.celebrate()`.
- Two of the ten states have **no live trigger in current
  gameplay** and are not faked: `sprint` (the runner's speed is
  fixed) and `climb` (no climbable surfaces exist). Both remain
  in the machine for future mechanics.
- Camera tracking, mode switching and autonomous play unchanged.

### Vehicle — INTEGRATED
- `VehicleController._build_visual()` builds
  `VehicleFactory.build(vehicle_kind)` (default SportsCar; env
  `IWT_VEHICLE`; `set_vehicle_kind()` rejects unknown kinds).
- The physics shape is resized from
  `VehicleFactory.collision_spec()` (SportsCar 1.7×0.85×3.4 —
  the same footprint class as the Phase 02 shape), so collision
  matches the factory model.
- `VehicleAnimation` is driven every physics frame with the real
  speed/steer/braking: all four wheel pivots spin from
  speed/wheel-radius, front pivots steer from the actual steer
  input, body brake-dive/acceleration-squat/bob apply, and
  `on_collision()` shakes the body on obstacle bumps.
- The AI controller's perception and input interface are
  untouched (perception reads level data, not visuals).

### Environment — INTEGRATED (all 8 worlds)
- `WorldManager.build()` takes the applied world name;
  `_build_decor()` now places `EnvironmentAssetLibrary.build_prop`
  props for that world at the **same roadside placements** Phase
  02 decor used (seeded RNG stream unchanged in structure:
  side, x = width/2 + 2.5..9.0, z along the level).
- Only **non-solid** library kinds are used as decor
  (`EnvironmentAssetLibrary.is_solid()` kinds — platform, road,
  bridge, tunnel — are excluded): decor never had collision and
  never blocks the route, the spawn, or the required path.
  Gameplay-critical structures (ground, strips, gap platforms,
  vehicle pad, finish arch) are the unchanged Phase 02/03
  builders. The legacy `_make_decor()` remains as a fallback for
  unknown worlds.

### Obstacles & collectibles — INTEGRATED
- Live obstacle types map to library kinds with
  affordance-preserving fix-ups in `_make_obstacle()`:
  jump → `jump_gate`, slide → `sliding_barrier`,
  block → `road_barrier`. The library centres its collision
  shape on the body origin while its mesh sits on top of the
  origin, so the shape is shifted up by half its height —
  collision and mesh then span exactly the same volume.
  Resulting live geometry: jump gate grounded, top at 1.0 m
  (jumpable; character jump apex ≈1.74 m); slide barrier
  underside at 1.2 m (slide capsule top is 0.9 m — the Phase 02
  gap, preserved); road barrier grounded. The slide kind's
  `moves` meta is forced false (live slide obstacles were
  always static). Pooling by live type is unchanged and reuses
  these bodies.
- Collectibles are the library `coin` (metadata score 10 — the
  value `GameManager` awards) with two live fix-ups: collision
  mask set to the player layer (the library ships mask 0, which
  could never fire `body_entered`) and the game's tuned 0.55
  detection radius kept. Pickup, scoring and progression are
  the original code paths.
- The library's other kinds (spike strip, ramp, moving barrier,
  star/gem collectibles, …) are **not** mapped: live gameplay
  has exactly three obstacle types and one collectible type,
  and inventing new gameplay was out of scope for this repair.

### Materials & VFX — INTEGRATED
- Obstacle/collectible colours now come through
  `MaterialLibrary.palette(world)` (falling back to the theme
  colours), matching the Phase 05 material library.
- One-shot Phase 05 VFX where valid: `collect_sparkle` on
  pickup, `celebrate_burst` on finish (`WorldManager.play_vfx`,
  self-freeing after 1.5 s; few, small, one-shot — performance
  safe by construction).
- Animation stays **procedural** (state-machine posing). No
  baked AnimationPlayer clips exist and none are claimed.

## 3. Visual QA (real pixels, Xvfb — `game/tests/visual_qa_test.gd`)

Method: the live `Main.tscn` under Xvfb at 1280×720, frames
grabbed after `RenderingServer.frame_post_draw`, checked
programmatically; screenshots saved to `screenshots/qa/`
(gitignored local evidence). Results (factory mode):

- Character in play (Nova selected live): frame rendered and
  varied; **182 Nova-purple-dominant pixels** in the window
  around the character's unprojected position (Nova body colour
  (0.65, 0.35, 0.85) exists only in the factory model).
- Vehicle in play (after a real `switch_mode()` transition —
  the transition frame is saved as `qa_transition.png`):
  **1,182 SportsCar-red-dominant pixels** around the vehicle
  (factory colour (0.9, 0.15, 0.2)); a driven vehicle frame
  also saved (`qa_vehicle.png`).
- All 8 worlds: top-strip sky average within **0.04–0.11** per
  channel of the world's theme sky colour, and Phase 05
  `Prop_<World>_*` nodes present in every world
  (`qa_world_<World>.png` × 8).
- Broadcast overlay: a frame with the Phase 06 overlay differs
  by MD5 from the same frame with it hidden
  (`qa_overlay.png`).
- Primitive mode (`IWT_FACTORY_VISUALS=0`) passes the same
  frame/sky/overlay sanity checks with signature checks
  skipped — the fallback is a real, working mode, not a stub.

Limitation, stated plainly: rendering here is llvmpipe
software rendering with no GPU. The checks above are mechanical
(colour signatures, sky match, pixel-change) — no claim is made
about how the frames would be judged aesthetically on real
hardware.

## 4. Performance (measured on this VM, before vs after)

Before = primitive mode (`IWT_FACTORY_VISUALS=0`, the Phase 02
builders, same binary). After = factory mode. Same machine,
same runs as the test suites:

| Measure | Before (primitive) | After (factory) |
|---|---|---|
| Character factory build (avg of 20) | n/a (primitive ≈ instant) | ≈4.9–5.8 ms |
| Vehicle factory build (avg of 20) | n/a | ≈2.0–2.2 ms |
| Prop build (avg of 20) | n/a | ≈1.0–1.6 ms |
| Live level build (start_game) | — | ≈28–31 ms |
| Live scene node count | — | 187–199 |
| Static memory (live scene, headless) | — | ≈33–35 MB |
| FPS, Xvfb 720p, 6 s autopilot | 3.67 | 3.50–3.67 |
| Pooling | bounded (Phase 03) | bounded, reuse verified (obstacles_reused > 0, pool ≤ caps) |

**This VM's 3–5 FPS is llvmpipe software-rendering-bound and
is not evidence about asset cost on real hardware.** Within
that bound, factory and primitive modes measure the same FPS;
the added cost is a few ms of build time per level and a
modest node-count increase, both bounded (pooling unchanged).

Visual/physics sync: factory visuals are children of the
physics controllers (character/vehicle) or placed by the same
builders as before (world), so they follow physics transforms
by construction; the logic suite verifies wheel spin/steer
angles and animation states against live physics values.

## 5. Tests

New suite: `tests/run_asset_integration_tests.sh` →
`tests/asset_integration_output.txt`, ending
`ASSET_INTEGRATION_DONE failures=0` — **87 checks, 0 failures**:

- Logic (headless, `AssetIntegrationTest.tscn`): factory
  character/vehicle live in the real `GameManager` (default
  selection, named parts/pivots, collision from factory spec),
  selection switching + rejection of unknown names, animation
  states run/jump/fall/land/slide/recover/celebrate from real
  play, wheel spin from speed and front-wheel steering from
  input, mode switching both ways, all 8 worlds' props
  (non-solid, off-route), obstacle library kinds + collision
  spans (jump grounded ≈1.0 m, slide gap ≥1.1 m, block
  grounded), coin collectibles with live pickup scoring,
  pooling bounded/reused, autopilot progress with factory
  visuals (121 decisions, 68.2 m travelled in 600 physics
  frames), 25 generated levels validate, dashboard bridge
  reports the real state (PLAYING) through its own command
  channel.
- **Guard test**: `_live_visuals_are_factory()` must hold in
  the integrated game; forcing the Phase 02 fallback
  (`set_factory_visuals_enabled(false)` — the same switch the
  `IWT_FACTORY_VISUALS=0` env uses) turns it false, and
  re-enabling restores it. All three guard checks pass, so a
  silent fallback in the live scene would fail this suite.
- Visual QA (Xvfb): §3 above, in both modes.

Regression: all pre-existing suites re-run fresh after the
integration — see the table in the commit/report; no existing
test's expectations were changed.

## 6. Files changed

- `game/scripts/character_controller.gd` — factory visual
  attach + fallback, `CharacterAnimation` driving, selection
  API (`set_character`, `set_factory_visual_enabled`,
  `visual_kind`, `factory_visual`, `animation_state`,
  `celebrate`).
- `game/scripts/vehicle_controller.gd` — factory visual attach
  + fallback, collision from `collision_spec()`,
  `VehicleAnimation` driving, selection API.
- `game/scripts/game_manager.gd` — selection config + env
  overrides (`IWT_CHARACTER`, `IWT_CHARACTER_VARIANT`,
  `IWT_VEHICLE`, `IWT_FACTORY_VISUALS`), `set_factory_visuals_enabled`,
  celebrate + finish VFX hooks, world name passed to
  `WorldManager.build()`.
- `game/scripts/world_manager.gd` — world-name/palette
  plumbing, library props for decor, library obstacles with
  alignment fix-ups, library coin collectibles, `play_vfx()`.
- `game/tests/asset_integration_test.gd` (+ `.tscn`),
  `game/tests/visual_qa_test.gd` (+ `.tscn`),
  `tests/run_asset_integration_tests.sh`,
  `tests/asset_integration_output.txt`.
- `.gitignore` — `screenshots/` (QA evidence, like
  `recordings/`).
- Docs: this file; `docs/PHASE05.md`, `docs/ARCHITECTURE.md`,
  `docs/PHASE10.md` updated to match the code.

## 7. Remaining limitations

- Visuals are still code-built primitive geometry — the
  Phase 05 factories' richer multi-part builds, not
  Blender-authored models. No Blender exists on this VM and
  no `.blend`/imported models exist or are claimed.
- `sprint` and `climb` animation states have no live gameplay
  trigger yet (fixed run speed; no climbable surfaces).
- Unmapped library kinds stay library-only (see §2) until a
  future phase designs gameplay for them.
- Real-hardware rendering performance is unmeasured (llvmpipe
  only, §4). YouTube-side and deployment readiness are
  unchanged from Phase 10.
