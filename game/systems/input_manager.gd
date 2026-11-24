extends Node
## InputManager - the only place that reads Input.
##
## Controllers ask for an intent Dictionary, never for a key. That is what lets the Phase 03
## AutonomousPlayer drive the same controllers by returning the same Dictionary, and it makes
## headless tests possible (a test sets `override_intent` and no keyboard is needed).

var override_intent: Dictionary = {}
var use_override := false

func intent() -> Dictionary:
	if use_override:
		return override_intent
	return {
		"move": Input.get_axis("move_left", "move_right"),
		"jump": Input.is_action_just_pressed("jump"),
		"jump_held": Input.is_action_pressed("jump"),
		"slide": Input.is_action_pressed("slide"),
		"accelerate": Input.get_axis("brake", "accelerate"),
		"steer": Input.get_axis("move_left", "move_right"),
		"switch_mode": Input.is_action_just_pressed("switch_mode"),
		"pause": Input.is_action_just_pressed("pause"),
	}

func set_override(d: Dictionary) -> void:
	override_intent = d
	use_override = true

func clear_override() -> void:
	use_override = false
	override_intent = {}
