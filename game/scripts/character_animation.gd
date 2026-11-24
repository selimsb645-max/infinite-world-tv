class_name CharacterAnimation
extends RefCounted
## Phase 05 — character animation system.
##
## A reusable animation state machine for the original characters.
## States: idle, run, sprint, jump, fall, land, slide, climb,
## celebrate, recover. Transitions are validated against an allowed
## map, so gameplay code cannot jump from e.g. "land" straight into
## "climb". update() poses the visual node (bob, lean, crouch) from
## the current state and the live movement values — no baked clips,
## so it works with every CharacterFactory variant.

const STATES: Array[String] = [
	"idle", "run", "sprint", "jump", "fall", "land",
	"slide", "climb", "celebrate", "recover",
]

const ALLOWED := {
	"idle": ["run", "sprint", "jump", "celebrate", "climb"],
	"run": ["idle", "sprint", "jump", "slide", "fall", "celebrate", "recover"],
	"sprint": ["run", "jump", "slide", "fall", "recover"],
	"jump": ["fall", "land", "slide"],
	"fall": ["land", "slide"],
	"land": ["idle", "run", "recover"],
	"slide": ["run", "idle", "recover"],
	"climb": ["idle", "run", "fall"],
	"celebrate": ["idle", "run"],
	"recover": ["idle", "run"],
}

var current: String = "idle"
var visual: Node3D
var _time_in_state: float = 0.0
var _bob_phase: float = 0.0

func _init(p_visual: Node3D = null) -> void:
	visual = p_visual

func state() -> String:
	return current

func time_in_state() -> float:
	return _time_in_state

func can_transition(to_state: String) -> bool:
	if not STATES.has(to_state):
		return false
	if to_state == current:
		return true
	return (ALLOWED.get(current, []) as Array).has(to_state)

## Returns true when the transition was accepted.
func transition_to(to_state: String) -> bool:
	if not can_transition(to_state):
		return false
	if to_state != current:
		current = to_state
		_time_in_state = 0.0
	return true

## Pose the visual from live movement. speed is m/s, airborne/sliding
## come from the controller, celebrating is set by gameplay events.
func update(delta: float, speed: float, airborne: bool, sliding: bool) -> void:
	_time_in_state += delta
	_bob_phase += delta * (4.0 + speed * 1.1)
	if visual == null:
		return
	var bob: float = 0.0
	var lean: float = 0.0
	var crouch: float = 1.0
	match current:
		"idle":
			bob = sin(_bob_phase * 0.6) * 0.02
		"run":
			bob = absf(sin(_bob_phase)) * 0.09
			lean = 0.12
		"sprint":
			bob = absf(sin(_bob_phase * 1.25)) * 0.12
			lean = 0.22
		"jump":
			bob = 0.12
			lean = -0.08
		"fall":
			bob = 0.05
			lean = -0.05
		"land":
			crouch = 0.82
			bob = -0.06
		"slide":
			crouch = 0.62
			lean = 0.3
		"climb":
			bob = absf(sin(_bob_phase * 0.8)) * 0.06
			lean = -0.15
		"celebrate":
			bob = absf(sin(_bob_phase * 1.6)) * 0.16
		"recover":
			bob = sin(_bob_phase * 0.8) * 0.04
			lean = -0.12
	# Auto-derive the locomotion state from movement when the caller
	# does not drive transitions itself.
	if airborne and current in ["run", "sprint", "idle"]:
		transition_to("jump")
	elif sliding and current in ["run", "sprint"]:
		transition_to("slide")
	elif not airborne and not sliding and current in ["jump", "fall"]:
		transition_to("land")
	visual.position.y = bob
	visual.rotation.x = lean
	visual.scale.y = crouch
