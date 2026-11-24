# INFINITE WORLD TV — Phase 04 Testing Report

Suite: `game/tests/autopilot_test.gd`
(`godot --headless --path game res://tests/AutopilotTest.tscn`)
Raw output: `tests/autopilot_output.txt`
Engine: Godot 4.3.stable, headless (dummy rendering driver).
Integration runs use `Engine.time_scale = 4.0`.

## Result: 29/29 checks PASS — `AUTOPILOT_DONE failures=0`, exit code 0

### Unit checks (decision logic on crafted perception snapshots)

| Check | Result |
|---|---|
| unit_jump_timed_for_barrier (dist 4.0 in the jump window) | PASS |
| unit_slide_timed_for_barrier (dist 3.0) | PASS |
| unit_block_avoided_by_steering (target_x = −3.4, strafe matches) | PASS |
| unit_no_jump_when_barrier_not_in_lane | PASS |
| unit_vehicle_slows_for_close_block (target speed 8.0) | PASS |
| unit_vehicle_steers_for_block (steer −1.00) | PASS |
| unit_vehicle_accelerates_on_open_road | PASS |
| recovery_first_action_is_jump — sequence `[jump, restart, jump, restart, jump, give_up]` | PASS |
| recovery_restarts_bounded (2 = MAX_RESTARTS_PER_LEVEL) | PASS |
| recovery_gives_up_exactly_once | PASS |
| tracker_history_bounded (kept 100 of 150) | PASS |
| tracker_success_rate_math (0.50) | PASS |
| adaptation_performance_nudge (`{deaths: 2, flawless: false}`) | PASS |
| adaptation_speed_scale_applies (cautious 9.1 vs default 13.0) | PASS |

### Integration checks (real game scene, real physics, no human input)

Endless procedural play started with a single
`GameManager.start_autonomous(777)` call — no Play press, no input
events anywhere in the suite.

| Check | Result / real numbers |
|---|---|
| starts_without_human_input | PASS |
| player_progresses_forward | PASS — 81.8 m into the then-current level at sampling time |
| character_mode_used / vehicle_mode_used | PASS / PASS |
| mode_switches_happen | PASS — 7 switches |
| autopilot_actions_executed | PASS — jumps 11, slides 11, brakes 3 (endless phase) |
| completes_multiple_consecutive_levels | PASS — 6 completed / 6 attempted |
| long_run_six_levels | PASS — 6 levels in 1,770 physics frames, 886 decisions |
| decision_interval_respected | PASS — 886 decisions ≤ 1,770 frames (0.08 s game-time interval; at time_scale 4 a physics frame is 0.0667 game-seconds, so ~1 decision per 2 frames is expected) |
| multiple_generated_worlds_played | PASS — Space World, Fantasy Islands, Neon City, Ocean World, Futuristic Highway, Desert World |
| recovery_never_loops_forever | PASS — max restarts in any endless level = 0 |
| still_playing_at_end | PASS |

**Endless-phase totals (AUTOPILOT_STATS):** decisions 886,
levels completed 6/6 (success rate 1.0 in this seeded run),
collisions 5, recovery events 11 (all first-strike jump/reverse;
no restarts, no give-ups), switches 7, jumps 11, slides 11, brakes 3.

### Recovery + handcrafted level (live, in-game)

The runner was placed head-on in front of Level 1's block
(−2.5, −61) with decisions frozen (interval 9999 s):

| Check | Result / real numbers |
|---|---|
| recovery_fires_when_wedged | PASS — recovery events 11 → 14, restarts 1 |
| recovery_restarts_bounded_live | PASS — restarts 1 ≤ 2 |
| autopilot_completes_handcrafted_level1 | PASS — Level 1 finished (index advanced to 1) in 150 physics frames after unfreezing |

**Final totals (AUTOPILOT_STATS_FINAL):** levels completed 7/7,
collisions 15 (the wedge test deliberately rams a block and the
recovery bumps are included — this number is not comparable to the
endless-phase 5), recoveries 14, switches 7, jumps 12, slides 13.

## Regression

| Suite | Result |
|---|---|
| Phase 02 smoke (`tests/smoke_output.txt`) | 26/26 PASS — `SMOKE_DONE failures=0` |
| Phase 03 generation (`tests/generation_output.txt`) | 45/45 PASS — `GEN_DONE failures=0`; 1,000 levels, 1,000 distinct fingerprints, 0 fallbacks, 3.76 s |

## Limitations (honest)

- Headless only: dummy rendering driver; no visual/FPS verification.
- Integration runs at `Engine.time_scale = 4.0` to fit CI time.
- Success rate 1.0 is the measured result for the seeded runs in
  this suite (endless seed 777, handcrafted Level 1) — reported as
  measured, not promised for arbitrary seeds.
- 11 first-strike recovery events during clean endless play show
  the stuck detector is conservative (it also trips on brief
  low-progress moments); escalation stayed bounded in every case.
