class_name AutonomousController
extends Node
## Phase 04 autonomous gameplay controller: the session owner that
## ties the Phase 04 modules together and plays the game end-to-end
## with NO human input.
##
##   PerceptionManager  (structured state from level data + bodies)
##        -> ActionPlanner (Character/Vehicle decision engines,
##           risk + route selection, mode-switch planning)
##        -> AutopilotInput (substituted InputManager — the real
##           CharacterController / VehicleController physics do the
##           moving, colliding, jumping and driving)
##   RecoveryManager watches for stuck states every physics frame
##   (bounded: jump/reverse -> restart -> give up once).
##   PerformanceTracker + GameplayStateManager record the session.
##
## Continuous progression needs no Play/Continue/Restart presses:
## finishing a level makes GameManager load the next generated level
## (Phase 03 endless mode), the finish signal re-arms the tracker,
## and play continues. Decisions run on a configurable interval
## (default 0.08 s), not per frame; only the cheap stuck check runs
## per physics frame.

var decision_interval: float = 0.08

var game = null
var input: AutopilotInput
var perception := PerceptionManager.new()
var planner := ActionPlanner.new()
var recovery := RecoveryManager.new()
var tracker := PerformanceTracker.new()
var state_manager := GameplayStateManager.new()

var enabled: bool = false
var decisions_made: int = 0

var _timer: float = 0.0
var _finish_pending: bool = false
var _level_open: bool = false
var _collision_cooldown: float = 0.0

## bumped_obstacle fires once per physics frame while a body stays in
## contact, so raw signal counts would inflate collisions wildly;
## count at most one collision per 0.35 s of contact.
func _on_bump() -> void:
    if _collision_cooldown > 0.0:
        return
    _collision_cooldown = 0.35
    tracker.note_collision()

## Adaptation (no external API): after each finished level, adjust
## the vehicle cruise-speed scale from the tracker's record — many
## collisions slow the car down a step, a flawless level speeds it
## up a step — and hand the DifficultyManager performance nudge to
## the level pipeline so the NEXT generated level eases or firms up.
func _adapt_after_level() -> void:
    if tracker.records.is_empty():
        return
    var last: Dictionary = tracker.records[tracker.records.size() - 1]
    var scale := planner.vehicle_engine.speed_scale
    if int(last["collisions"]) >= 6:
        scale = clampf(scale - 0.08, 0.7, 1.05)
    elif bool(last["completed"]) and int(last["collisions"]) == 0:
        scale = clampf(scale + 0.03, 0.7, 1.05)
    planner.vehicle_engine.speed_scale = scale
    if game.transition_manager != null:
        game.transition_manager.performance_hint = tracker.performance_for_generator()

func setup(game_node) -> void:
    game = game_node
    input = AutopilotInput.new()
    input.name = "AutopilotInput"
    game.add_child(input)
    game.input_manager = input
    game.character.input_manager = input
    game.vehicle.input_manager = input
    game.character.bumped_obstacle.connect(_on_bump)
    game.vehicle.bumped_obstacle.connect(_on_bump)
    game.world_manager.finish_reached.connect(_on_finish_reached_signal)

## Starts endless procedural play (Phase 03) under autopilot.
func start_endless(base_seed: int) -> void:
    game.start_endless(base_seed)
    _open_level_tracking()
    enabled = true

## Starts the current handcrafted level under autopilot.
func start_handcrafted() -> void:
    game.start_game("character", "")
    _open_level_tracking()
    enabled = true

func stop() -> void:
    enabled = false
    if input != null:
        input.stop_all()
    state_manager.stop()

func current_level() -> Dictionary:
    if bool(game.endless_active):
        var gen: Dictionary = game.get("_current_generated")
        return gen.get("level", {})
    return game.level_manager.current_level()

func stats() -> Dictionary:
    return {
        "decisions": decisions_made,
        "levels_completed": state_manager.levels_completed,
        "levels_attempted": tracker.attempted(),
        "success_rate": tracker.success_rate(),
        "collisions": tracker.total_collisions,
        "recoveries": tracker.total_recoveries,
        "recovery_events": recovery.events,
        "switches": tracker.total_switches,
        "jumps": planner.character_engine.jumps_made,
        "slides": planner.character_engine.slides_made,
        "brakes": planner.vehicle_engine.brakes_applied,
        "records_kept": tracker.records.size(),
        "phase": state_manager.phase,
    }

func _open_level_tracking() -> void:
    var level := current_level()
    tracker.begin_level(int(level.get("level_number", 1)),
        str(level.get("world", level.get("theme", ""))))
    state_manager.start(int(level.get("level_number", 1)))
    recovery.reset_for_level()
    _level_open = true

func _on_finish_reached_signal() -> void:
    _finish_pending = true

func _physics_process(delta: float) -> void:
    if not enabled or game == null:
        return
    if int(game.state) != 1:  # GameManager.State.PLAYING
        return
    tracker.note_frame()
    if _collision_cooldown > 0.0:
        _collision_cooldown -= delta
    if _finish_pending:
        _finish_pending = false
        tracker.finish_level(true)
        _adapt_after_level()
        var level := current_level()
        state_manager.level_finished(int(level.get("level_number",
            state_manager.current_level_number + 1)))
        _open_level_tracking()
    # Bounded recovery check (position-only, every physics frame).
    var ctrl = game.active_controller()
    if ctrl == null:
        # Phase 09 — no active body during a mode switch / level
        # transition: skip this tick instead of dereferencing null.
        return
    var rec := recovery.update(delta,
        {"pos": ctrl.global_position, "mode": str(game.mode)}, true)
    match str(rec["action"]):
        "jump":
            input.press_jump()
            tracker.note_recovery(false)
            state_manager.set_recovering(true)
        "reverse":
            input.set_controls(0.0, -1.0)
            tracker.note_recovery(false)
            state_manager.set_recovering(true)
        "restart":
            tracker.note_recovery(true)
            game.restart_level()
            state_manager.set_recovering(false)
        "give_up":
            tracker.note_recovery(true)
            _request_new_level()
        _:
            state_manager.set_recovering(false)
    # Timed decisions.
    _timer -= delta
    if _timer > 0.0:
        return
    _timer = decision_interval
    var p := perception.sense(game, current_level())
    if not bool(p.get("available", true)):
        # Phase 09 — perception unavailable this interval (no
        # active controller): hold course, decide next interval.
        return
    var action := planner.plan(p, str(game.mode))
    decisions_made += 1
    if bool(action.get("switch_mode", false)):
        game.switch_mode()
        tracker.note_switch()
        return
    input.set_controls(float(action["strafe"]), float(action["throttle"]))
    if bool(action.get("jump", false)):
        input.press_jump()
    if bool(action.get("slide", false)):
        input.press_slide()

func _request_new_level() -> void:
    if _level_open:
        tracker.finish_level(false)
        _adapt_after_level()
        _level_open = false
    game.autopilot_request_new_level()
    _open_level_tracking()
