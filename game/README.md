# game/ — Godot 4 project (Phase 02)

## Run it locally

1. Install **Godot 4.3** (standard build, not .NET).
2. Open Godot → Import → select `game/project.godot`.
3. Press **F5**.

No assets to download, no addons to install: every mesh is generated in GDScript.

## Controls

| Action | Character mode | Vehicle mode |
|---|---|---|
| Move | A / D (strafe, clamped to the lane) | A / D (steer) |
| Jump | Space or W | — |
| Slide | S or Shift | — |
| Accelerate / brake | — | W / S |
| Switch mode | Tab or E | Tab or E |
| Pause | Esc or P | Esc or P |

## Structure

```
core/       game_manager.gd (state machine + mode switch), world_manager.gd (themes),
            level_manager.gd (the 5 handcrafted levels, as data)
entities/   character_controller.gd, vehicle_controller.gd, camera_controller.gd
systems/    input_manager.gd (the only place that reads Input), collision_manager.gd
            (layer numbers + colliders), audio_manager.gd (generated tones)
ui/         game_ui.gd (menu, HUD, pause, complete, settings)
scenes/     main.tscn (one node; everything else is composed in scripts/main.gd)
scripts/    main.gd (composition root)
tests/      test_runner.gd (headless suite, 37 checks)
```

## Design notes that matter later

- **InputManager returns an intent Dictionary.** Controllers never read `Input` directly, so the
  Phase 03 AutonomousPlayer drives the same code by returning the same Dictionary, and tests run
  with no keyboard.
- **A level is data, not a scene.** `LevelManager.get_level(i)` returns a Dictionary. The Phase 03
  generator will emit the same shape, so nothing downstream changes.
- **The camera reads a target node, not a controller type.** A mode switch re-targets it in the
  same frame, which is why "no broken camera states" holds.

## Tests

```bash
../Godot_v4.3-stable_linux.x86_64 --headless --path . --script res://tests/test_runner.gd
```

Current result: 37/37 passed. See `../docs/TESTING.md` for the report and the known limitations.
