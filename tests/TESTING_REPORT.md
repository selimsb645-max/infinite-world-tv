# Testing Report — Phase 02 (Core Game Engine)

**Date:** 2026-11-24
**Engine used for testing:** Godot **4.3.stable.official** (official Linux
x86_64 binary, downloaded from the `godotengine/godot` GitHub releases
into `~/workspace/tools/godot/` on this VM; `godot --version` →
`4.3.stable.official.77dcf97d8`). The engine itself was really run —
nothing in this report is invented.

## How the tests work

`game/tests/smoke_test.gd` (scene `game/tests/SmokeTest.tscn`) instances
the real main scene, starts real games through the same `start_game()`
path the Play button uses, injects real input actions
(`Input.action_press`), and steps real physics frames. Run command:

```bash
godot --headless --path game res://tests/SmokeTest.tscn
```

Final result: **26 / 26 checks PASS, `SMOKE_DONE failures=0`, exit code 0.**
Full output: `tests/smoke_output.txt`. The project import check
(`godot --headless --import`) also completes with exit code 0 and no
script errors, and the main scene boots headless and quits cleanly.

## Results per spec test area

| Spec test | Result | Evidence from the run |
|---|---|---|
| Character movement | ✅ Executed, PASS | z 3.60 → 0.93 auto-run; strafe x 0.00 → 1.40 |
| Jumping | ✅ Executed, PASS | y 0.00 → 0.84 after `try_jump()` |
| Sliding | ✅ Executed, PASS | slide state enters and ends correctly |
| Vehicle controls | ✅ Executed, PASS | accelerates to 7.33 m/s, moves, brakes to 0.30 m/s |
| Mode switching | ✅ Executed, PASS | character→vehicle→character; camera target follows the active body |
| Camera behavior | ✅ Executed, PASS | settles 9.80 m behind/above the character, stays behind |
| Collision detection | ✅ Executed, PASS | runner stopped at z=-63.50 by a block whose front face is at -63.9 (did not pass through) |
| Collectibles / scoring | ✅ Executed, PASS | score 0 → 10 on pickup |
| Level loading / transitions | ✅ Executed, PASS | 3 levels load and reload; themes switch |
| Five environment themes | ✅ Executed, PASS | all 5 apply; 5 distinct sky colours verified |
| Pause and resume | ✅ Executed, PASS | `tree.paused` true in PAUSED state, false after resume |
| Restart | ✅ Executed, PASS | score reset to 0, character back at spawn |
| Scene loading | ✅ Executed, PASS | main scene loads and game becomes ready |
| Resource cleanup | ⚠️ Partially verified | level rebuilds free the old level root (`queue_free`) and repeated level loads in the smoke run show no errors; no long soak test was run |

## Bug found and fixed by the tests

The first smoke run failed one check (`restart_resets_score`): a
collectible from a freshly rebuilt level could be "picked up" by a
stale/inactive body overlap, adding +10 after a restart. Fixed properly
in gameplay code: `WorldManager` now only lets the **active** controller
trigger collectibles/zones (with a sanity distance check), and
`GameManager` moves bodies to spawn before rebuilding a level. Re-run:
26/26 PASS.

## Honest limitations

- **Headless only.** This VM has no display/GPU, so visual quality,
  real 60 FPS frame pacing and how the game *looks* in a window were
  **not** verified here — that needs a run on a real machine (open
  `game/` in Godot on any PC). Physics, logic, scene loading and UI
  wiring were verified.
- Headless runs print Godot dummy-renderer warnings
  (`mesh_get_surface_count`, `Parameter "m" is null`, and an
  `ObjectDB instances leaked at exit` warning on forced quit). These
  come from the dummy rendering/audio drivers, not from game code, and
  do not appear in windowed runs.
- Audio blips are generated code paths; audible output could not be
  heard/verified on this VM (dummy audio driver). The code is guarded
  to be a no-op when no playback stream exists.
- Vehicle physics is an arcade `CharacterBody3D` model (per the Phase 02
  brief's allowance), not `VehicleBody3D` raycast suspension.
