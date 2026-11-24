# INFINITE WORLD TV — Phase 04: AI Autonomous Gameplay Controller

Phase 04 adds an autonomous player that plays the game end-to-end with
**no human input**: it perceives the level as structured data, decides
with rule-based + predictive engines, and drives the *real* Phase 02
character/vehicle controllers through their existing input interface,
so all movement, jumping, sliding, driving and colliding happens in
the real physics engine. No screenshot AI, no external/paid AI API,
no teleporting (the only position resets are the game's own mode
switch and the documented recovery restart/skip actions).

## How to run it

```gdscript
# From code (e.g. a future streaming bootstrap):
game.start_autonomous(777)        # endless procedural play, autopilot on
# or attach to the handcrafted levels:
game.autonomous_controller.start_handcrafted()
```

Headless verification:

```bash
godot --headless --path game res://tests/AutopilotTest.tscn
# -> AUTOPILOT_DONE failures=0   (see tests/TESTING_REPORT_PHASE04.md)
```

## Architecture

```
GameManager.start_autonomous(seed)
        │
        ▼
AutonomousController (session owner, Node)
  ├─ PerceptionManager      structured snapshot at the decision
  │                         interval (default 0.08 s, configurable):
  │                         position/speed/heading/grounded, obstacles
  │                         ahead with distances, gaps, current segment
  │                         + mode, route lane, collectibles, finish
  │                         distance. Level data is the world model;
  │                         physics remains ground truth.
  ├─ ActionPlanner          picks the mode engine, adds the
  │   │                     mode-switch plan (switch when the player
  │   │                     crosses into a segment of the other mode;
  │   │                     GameManager.switch_mode() brings the other
  │   │                     body to the player, as for a human).
  │   ├─ CharacterDecisionEngine ─ RiskAssessmentManager (jump/slide
  │   │                            trigger windows derived from the real
  │   │                            jump physics: v=9.5, g=26, run 8 m/s;
  │   │                            block avoidance) + RouteSelectionManager
  │   └─ VehicleDecisionEngine ── RiskAssessmentManager (cruise speed
  │                                13, slower near blocks / on curve,
  │                                bridge, tunnel segments; brake on
  │                                overshoot) + RouteSelectionManager;
  │                                steering = lane error + heading
  │                                correction (no impossible maneuvers:
  │                                the car turns only through its real
  │                                arcade steering at speed)
  ├─ AutopilotInput         an InputManager substitute. The Phase 02
  │                         controllers only ever read input through
  │                         InputManager, so swapping this node in gives
  │                         the AI control through the exact human
  │                         interface — physics and collisions untouched.
  ├─ RecoveryManager        per-physics-frame stuck watch (net
  │                         displacement < 0.45 m over a 1.1 s window).
  │                         Escalation, strictly bounded per level:
  │                         jump (character) / 0.5 s reverse (vehicle)
  │                         → restart level (max 2) → give up once and
  │                         request a fresh level via
  │                         GameManager.autopilot_request_new_level()
  │                         (advances WITHOUT the finish bonus).
  │                         Every event is logged in the tracker.
  ├─ GameplayStateManager   IDLE → PLAYING ⇄ RECOVERING → LEVEL_DONE …
  └─ PerformanceTracker     bounded per-level records (cap 100):
                            completed?, collisions (0.35 s contact
                            cooldown so one bump ≠ 60 counts),
                            recoveries, restarts, switches, world.
```

## Continuous play

Finishing a level fires WorldManager.finish_reached; GameManager
(Phase 03 endless mode) loads the pregenerated next level, the
controller closes the tracker's record, re-arms for the new level and
keeps driving. No Play / Continue / Restart press is ever needed.
In the verified headless run the autopilot completed **6 consecutive
generated levels across 6 different worlds** and then a handcrafted
Phase 02 level, still playing at the end (see the testing report for
the full real numbers).

## Adaptation (local, no external API)

After each level the PerformanceTracker record drives two bounded
adjustments:

- **Vehicle cruise scale** (0.70–1.05): ≥6 collisions in a level steps
  it down 0.08; a flawless completion steps it up 0.03.
- **Generation difficulty nudge**: the tracker emits the Phase 03
  DifficultyManager performance contract (`{"deaths": restarts,
  "flawless": bool}`); AutonomousController stores it as
  `LevelTransitionManager.performance_hint`, so upcoming generated
  levels ease after repeated restarts and firm up after flawless runs
  (the nudge itself is capped at ±0.05 by DifficultyManager).

The decision engines are pure functions of the perception snapshot,
so a learned model could later replace or advise them behind the
same interface; nothing in Phase 04 depends on that.

## Performance

- Decisions run on a configurable interval (default 0.08 s), never
  per frame; perception is O(obstacles + segments) over a 34 m
  lookahead window.
- Only the position-only stuck check runs per physics frame.
- Tracker history is capped at 100 records; the level pipeline still
  retains at most 2 level definitions (Phase 03) — long runs do not
  grow memory.

## Honest limitations

- **Headless only.** All verification ran with Godot's dummy rendering
  driver; on-screen look/FPS of autopilot play is unverified.
- **Test runs use `Engine.time_scale = 4`** so long runs fit in CI
  time; the decision interval is in game-time seconds, so behaviour
  scales, but real-time 1× pacing is exercised only implicitly.
- First-strike recoveries (jump/reverse) fired 11 times during the
  6-level endless run even though no level needed a restart — the
  stuck window also trips on brief low-progress moments (e.g. a car
  easing around a block). They are harmless but show the threshold
  is conservative, not perfect.
- Gap segments are crossed on their spanning platform via the route
  lane; the misaligned-runner jump is a fallback, and platform-step
  climbing relies on recovery jumps rather than a dedicated step
  planner.
- Success rates in the testing report are from the seeded test runs
  (seed 777 endless + handcrafted Level 1), not a guarantee for every
  seed; the report states the actual numbers measured.
