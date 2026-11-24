class_name CameraController
extends Node3D
## Single shared follow camera for both gameplay modes. The rig lerps
## toward a mode-specific offset behind the target and the camera looks
## slightly ahead of the target, so mode switches never snap or break:
## only the target and offset change.

var target: Node3D
var mode: String = "character"

## Phase 06: broadcast framing multiplier on the follow offset
## (1.0 = the original Phase 02 framing, unchanged). The
## CameraCaptureController eases this with speed; nothing else in
## the game sets it.
var distance_scale: float = 1.0

func set_distance_scale(value: float) -> void:
	distance_scale = clampf(value, 0.75, 1.6)

var _camera: Camera3D
var _offsets := {
	"character": Vector3(0, 4.6, 8.5),
	"vehicle": Vector3(0, 5.6, 11.0),
}

func _init() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 62.0
	_camera.near = 0.1
	_camera.far = 300.0
	add_child(_camera)

func _ready() -> void:
	_camera.current = true
	global_position = Vector3(0, 4.6, 10.0)

func set_target(new_target: Node3D, new_mode: String) -> void:
	target = new_target
	mode = new_mode

func snap_to_target() -> void:
	if target != null:
		global_position = target.global_position + _offsets.get(mode, _offsets["character"]) * distance_scale

func camera() -> Camera3D:
	return _camera

func _process(delta: float) -> void:
	if target == null:
		return
	var offset: Vector3 = _offsets.get(mode, _offsets["character"]) * distance_scale
	var desired: Vector3 = target.global_position + offset
	var weight := 1.0 - exp(-5.0 * delta)
	global_position = global_position.lerp(desired, weight)
	var look_point: Vector3 = target.global_position + Vector3(0, 1.4, -4.0)
	if global_position.distance_squared_to(look_point) > 0.01:
		_camera.look_at(look_point, Vector3.UP)
