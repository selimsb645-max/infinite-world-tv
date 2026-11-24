class_name GameplayStateManager
extends RefCounted
## Phase 04 gameplay state machine for the autonomous session:
## IDLE -> PLAYING -> (RECOVERING) -> PLAYING -> LEVEL_DONE -> PLAYING
## ... -> STOPPED. Kept deliberately tiny: it exists so the
## controller, the tracker and the tests all read one shared,
## inspectable state instead of scattered flags.

enum Phase { IDLE, PLAYING, RECOVERING, LEVEL_DONE, STOPPED }

var phase: int = Phase.IDLE
var current_level_number: int = 0
var levels_completed: int = 0

func start(level_number: int) -> void:
    current_level_number = level_number
    phase = Phase.PLAYING

func set_recovering(value: bool) -> void:
    if phase == Phase.PLAYING and value:
        phase = Phase.RECOVERING
    elif phase == Phase.RECOVERING and not value:
        phase = Phase.PLAYING

func level_finished(new_level_number: int) -> void:
    levels_completed += 1
    current_level_number = new_level_number
    phase = Phase.PLAYING

func stop() -> void:
    phase = Phase.STOPPED

func is_playing() -> bool:
    return phase == Phase.PLAYING or phase == Phase.RECOVERING
