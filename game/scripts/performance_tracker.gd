class_name PerformanceTracker
extends RefCounted
## Phase 04 performance tracking: one bounded record per attempted
## level (history capped, so long autonomous runs cannot grow memory
## without limit). Feeds two things: the documented success rates in
## the Phase 04 test report, and the Phase 03 DifficultyManager's
## performance nudge ({"deaths": int, "flawless": bool}) for the next
## generated level.

const MAX_RECORDS := 100

var records: Array[Dictionary] = []
var total_collisions: int = 0
var total_recoveries: int = 0
var total_switches: int = 0

var _current: Dictionary = {}

func begin_level(level_number: int, world: String) -> void:
    _current = {"level_number": level_number, "world": world,
        "completed": false, "collisions": 0, "recoveries": 0,
        "switches": 0, "restarts": 0, "frames": 0}

func note_collision() -> void:
    total_collisions += 1
    if not _current.is_empty():
        _current["collisions"] = int(_current["collisions"]) + 1

func note_recovery(restarted: bool) -> void:
    total_recoveries += 1
    if not _current.is_empty():
        _current["recoveries"] = int(_current["recoveries"]) + 1
        if restarted:
            _current["restarts"] = int(_current["restarts"]) + 1

func note_switch() -> void:
    total_switches += 1
    if not _current.is_empty():
        _current["switches"] = int(_current["switches"]) + 1

func note_frame() -> void:
    if not _current.is_empty():
        _current["frames"] = int(_current["frames"]) + 1

func finish_level(completed: bool) -> Dictionary:
    if _current.is_empty():
        return {}
    _current["completed"] = completed
    records.append(_current.duplicate())
    while records.size() > MAX_RECORDS:
        records.pop_front()
    var done := _current
    _current = {}
    return done

func attempted() -> int:
    return records.size()

func completed_count() -> int:
    var n := 0
    for r in records:
        if bool(r["completed"]):
            n += 1
    return n

func success_rate() -> float:
    if records.is_empty():
        return 0.0
    return float(completed_count()) / float(records.size())

## DifficultyManager (Phase 03) performance contract.
func performance_for_generator() -> Dictionary:
    if records.is_empty():
        return {}
    var last: Dictionary = records[records.size() - 1]
    return {"deaths": int(last["restarts"]),
        "flawless": bool(last["completed"]) and int(last["collisions"]) == 0}
