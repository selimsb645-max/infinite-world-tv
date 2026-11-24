class_name InputManager
extends Node
## Central wrapper around the Input actions defined in project.godot.
## Controllers read input only through here, so tests and future
## autonomous control can substitute this node without touching gameplay code.

func strafe_axis() -> float:
	return Input.get_axis("move_left", "move_right")

func throttle_axis() -> float:
	## +1 accelerating, -1 braking (vehicle mode).
	return Input.get_axis("brake", "accelerate")

func jump_just_pressed() -> bool:
	return Input.is_action_just_pressed("jump")

func slide_just_pressed() -> bool:
	return Input.is_action_just_pressed("slide")

func slide_pressed() -> bool:
	return Input.is_action_pressed("slide")

func pause_just_pressed() -> bool:
	return Input.is_action_just_pressed("pause")

func switch_just_pressed() -> bool:
	return Input.is_action_just_pressed("switch_mode")
