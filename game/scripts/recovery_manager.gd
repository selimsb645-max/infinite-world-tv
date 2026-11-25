class_name RecoveryManager
extends RefCounted
## Phase 04 failure recovery, strictly bounded so it can never loop
## forever:
##   stuck detected -> recovery 1: jump (character) / reverse burst
##                     (vehicle)
##   stuck again    -> recovery 2: restart the level (max
##                     MAX_RESTARTS_PER_LEVEL times per level)
##   still stuck    -> give up on this level and request a fresh one
##                     (AutonomousController asks GameManager for the
##                     next level); the request fires once.
## Every event is counted and reported to the PerformanceTracker.

const STUCK_WINDOW := 1.1
const STUCK_DISTANCE := 0.45
const MAX_RESTARTS_PER_LEVEL := 2

var events: int = 0
var restarts_this_level: int = 0

var _window_pos: Vector3 = Vector3.ZERO
var _window_started: bool = false
var _still_time: float = 0.0
var _recoveries_this_stuck: int = 0
var _gave_up: bool = false
var _reverse_timer: float = 0.0

func reset_for_level() -> void:
    restarts_this_level = 0
    _recoveries_this_stuck = 0
    _still_time = 0.0
    _gave_up = false
    _reverse_timer = 0.0
    _window_started = false

## Returns {"action": "none"|"jump"|"reverse"|"restart"|"give_up"}.
func update(delta: float, p: Dictionary, playing: bool) -> Dictionary:
    if not playing:
        return {"action": "none"}
    if not p.has("pos"):
        # Phase 09 — perception data unavailable: degrade to no
        # action instead of raising an invalid-index error.
        return {"action": "none"}
    if _reverse_timer > 0.0:
        _reverse_timer -= delta
        return {"action": "reverse"}
    var pos: Vector3 = p["pos"]
    # Stuck = net displacement from the window's anchor position stays
    # under STUCK_DISTANCE for the whole STUCK_WINDOW. (Comparing
    # per-frame movement instead would false-trigger constantly: at
    # 60 fps even a full-speed runner moves only ~0.13 m per frame.)
    if not _window_started:
        _window_pos = pos
        _window_started = true
    var moved := Vector2(pos.x - _window_pos.x, pos.z - _window_pos.z).length()
    if moved > STUCK_DISTANCE:
        _window_pos = pos
        _still_time = 0.0
        _recoveries_this_stuck = 0
        return {"action": "none"}
    _still_time += delta
    if _still_time < STUCK_WINDOW:
        return {"action": "none"}
    _still_time = 0.0
    _window_pos = pos
    events += 1
    _recoveries_this_stuck += 1
    if _recoveries_this_stuck == 1:
        if str(p["mode"]) == "vehicle":
            _reverse_timer = 0.5
            return {"action": "reverse"}
        return {"action": "jump"}
    if restarts_this_level < MAX_RESTARTS_PER_LEVEL:
        restarts_this_level += 1
        _recoveries_this_stuck = 0
        return {"action": "restart"}
    if not _gave_up:
        _gave_up = true
        return {"action": "give_up"}
    return {"action": "none"}
