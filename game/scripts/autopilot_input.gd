class_name AutopilotInput
extends InputManager
## Phase 04: virtual input source driven by the autonomous controller.
## GameManager's own comment on InputManager anticipated exactly this:
## controllers read input only through InputManager, so substituting
## this node gives the AI full control through the REAL physics and
## collision systems without touching gameplay code. Human pause /
## switch actions are disabled here on purpose (the autopilot drives
## mode switches through GameManager.switch_mode() itself).

var _strafe: float = 0.0
var _throttle: float = 0.0
var _jump_edge: bool = false
var _slide_edge: bool = false

func set_controls(strafe: float, throttle: float) -> void:
    _strafe = clampf(strafe, -1.0, 1.0)
    _throttle = clampf(throttle, -1.0, 1.0)

func press_jump() -> void:
    _jump_edge = true

func press_slide() -> void:
    _slide_edge = true

func stop_all() -> void:
    _strafe = 0.0
    _throttle = 0.0
    _jump_edge = false
    _slide_edge = false

func strafe_axis() -> float:
    return _strafe

func throttle_axis() -> float:
    return _throttle

func jump_just_pressed() -> bool:
    var v := _jump_edge
    _jump_edge = false
    return v

func slide_just_pressed() -> bool:
    var v := _slide_edge
    _slide_edge = false
    return v

func slide_pressed() -> bool:
    return false

func pause_just_pressed() -> bool:
    return false

func switch_just_pressed() -> bool:
    return false
