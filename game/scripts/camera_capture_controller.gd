class_name CameraCaptureController
extends Node
## Phase 06 — broadcast framing on top of the Phase 02
## CameraController. It does not replace the follow rig; it observes
## the game and gently adapts it for capture:
##   * dynamic distance — the rig pulls back smoothly as the active
##     controller speeds up (vehicle more than character), so fast
##     gameplay stays framed instead of outrunning the camera;
##   * smooth transitions — distance changes are lerped, and mode
##     switches are counted, never snapped (the rig itself already
##     lerps position; this layer only scales its offset);
##   * environment-aware framing — the current world is tracked from
##     the EnvironmentManager so overlays and the audio mixer agree
##     with what the camera is showing;
##   * horizon stability — the rig never rolls; is_horizon_stable()
##     verifies the camera's roll stays at zero;
##   * obstacle visibility — is_point_visible() tests whether a world
##     point is inside the camera frustum (used by tests and by any
##     future "keep the next obstacle on screen" logic).

var rig: CameraController
var game: Node  # GameManager (untyped to avoid a cyclic dependency)

var current_world: String = ""
var current_mode: String = ""
var distance_scale: float = 1.0
var mode_transitions: int = 0

var _bound: bool = false

func bind(camera_rig: CameraController, game_manager: Node) -> void:
	rig = camera_rig
	game = game_manager
	_bound = rig != null and game != null
	if _bound:
		current_mode = str(game.get("mode"))
		current_world = str(game.get("environment_manager").get("current_theme"))

func _process(delta: float) -> void:
	if not _bound:
		return
	var new_mode := str(game.get("mode"))
	if new_mode != current_mode:
		current_mode = new_mode
		mode_transitions += 1
	current_world = str(game.get("environment_manager").get("current_theme"))
	var speed := 0.0
	var ctrl: Object = game.call("active_controller")
	if ctrl != null:
		speed = float(ctrl.call("current_speed"))
	var per_mode := 0.014 if current_mode == "vehicle" else 0.010
	var desired := clampf(1.0 + speed * per_mode, 1.0, 1.35)
	var weight := 1.0 - exp(-2.5 * delta)
	distance_scale = lerpf(distance_scale, desired, weight)
	rig.set_distance_scale(distance_scale)

func is_horizon_stable() -> bool:
	if rig == null or rig.camera() == null:
		return false
	return absf(rig.camera().global_rotation_degrees.z) < 1.0

func is_point_visible(point: Vector3) -> bool:
	if rig == null or rig.camera() == null:
		return false
	var cam := rig.camera()
	if cam.is_position_behind(point):
		return false
	var to_point := (point - cam.global_position).normalized()
	var forward := -cam.global_transform.basis.z.normalized()
	var limit := cos(deg_to_rad(cam.fov * 0.75))
	return forward.dot(to_point) > limit

func stats() -> Dictionary:
	return {
		"world": current_world,
		"mode": current_mode,
		"distance_scale": distance_scale,
		"mode_transitions": mode_transitions,
		"horizon_stable": is_horizon_stable(),
	}
