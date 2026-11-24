extends Camera3D
## CameraController - smooth follow that changes framing per gameplay mode.
##
## The camera is lerped, never snapped, and it reads a target Node3D instead of a controller
## type, so a mode switch cannot leave it looking at a freed node (Phase 02 requirement:
## "no broken camera states").

@export var follow_distance := 7.5
@export var follow_height := 3.6
@export var look_height := 1.2
@export var smoothing := 6.0

var target: Node3D
var mode := "character"

func set_target(node: Node3D, new_mode: String = "character") -> void:
	target = node
	mode = new_mode

func _ready() -> void:
	# mode-specific framing: the racer sits lower and further back
	follow_distance = 7.5
	follow_height = 3.6

func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var want_dist := 7.5 if mode == "character" else 10.5
	var want_height := 3.6 if mode == "character" else 4.8
	var want_look := 1.2 if mode == "character" else 1.0

	follow_distance = lerpf(follow_distance, want_dist, min(1.0, delta * 3.0))
	follow_height = lerpf(follow_height, want_height, min(1.0, delta * 3.0))
	look_height = lerpf(look_height, want_look, min(1.0, delta * 3.0))

	var desired := target.global_position + Vector3(0, follow_height, follow_distance)
	global_position = global_position.lerp(desired, min(1.0, delta * smoothing))
	var look_at_point := target.global_position + Vector3(0, look_height, -6.0)
	look_at(look_at_point, Vector3.UP)
