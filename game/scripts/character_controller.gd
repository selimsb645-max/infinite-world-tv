class_name CharacterController
extends CharacterBody3D
## Cartoon runner. Auto-runs forward (-Z), strafes with
## move_left/move_right, jumps and slides. Physics via
## CharacterBody3D.move_and_slide() — the physics body is always the
## authority; the visual is a child that only follows it.
##
## Phase 05.1: the visual is a CharacterFactory model (Phase 05)
## posed by the CharacterAnimation state machine from real gameplay
## state. The original Phase 02 primitive visual remains available
## via factory_visual_enabled = false (tools/tests fallback) and is
## built by the exact original code path.

signal bumped_obstacle

const RUN_SPEED := 8.0
const STRAFE_SPEED := 7.0
const JUMP_VELOCITY := 9.5
const GRAVITY := 26.0
const SLIDE_TIME := 0.65

var active: bool = false
var sliding: bool = false
var input_manager: InputManager

## Phase 05.1: which factory character/variant this runner shows.
var character_name: String = "Pip"
var character_variant: int = 0
## Phase 05.1: true = Phase 05 factory visual; false = Phase 02
## primitive visual (fallback / comparison mode).
var factory_visual_enabled: bool = true

var _slide_timer: float = 0.0
var _bob_phase: float = 0.0
var _visual: Node3D
var _factory_visual: Node3D
var _anim: CharacterAnimation
var _recover_timer: float = 0.0
var _celebrate_timer: float = 0.0
var _shape_node: CollisionShape3D
var _stand_shape: CapsuleShape3D
var _slide_shape: CapsuleShape3D
var _was_airborne: bool = false

func _init() -> void:
	collision_layer = CollisionManager.LAYER_PLAYER
	collision_mask = CollisionManager.LAYER_WORLD | CollisionManager.LAYER_OBSTACLE
	_stand_shape = CapsuleShape3D.new()
	_stand_shape.radius = 0.4
	_stand_shape.height = 1.8
	_slide_shape = CapsuleShape3D.new()
	_slide_shape.radius = 0.4
	_slide_shape.height = 0.9
	_shape_node = CollisionShape3D.new()
	_shape_node.shape = _stand_shape
	_shape_node.position.y = 0.9
	add_child(_shape_node)
	_build_visual()

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if factory_visual_enabled:
		_build_factory_visual()
	else:
		_build_primitive_visual()

## Phase 05.1: build the Phase 05 factory model under the Visual
## container and bind the animation state machine to it.
func _build_factory_visual() -> void:
	_clear_visual_children()
	_factory_visual = CharacterFactory.build(character_name, character_variant)
	if _factory_visual == null:
		character_name = "Pip"
		character_variant = 0
		_factory_visual = CharacterFactory.build(character_name, character_variant)
	_visual.add_child(_factory_visual)
	_anim = CharacterAnimation.new(_factory_visual)

func _clear_visual_children() -> void:
	if _visual == null:
		return
	for child in _visual.get_children():
		_visual.remove_child(child)
		child.queue_free()
	_factory_visual = null
	_anim = null

## Switch the live character to another factory character/variant.
## Returns false (and changes nothing) for an unknown name.
func set_character(new_name: String, variant: int = -1) -> bool:
	if CharacterFactory.spec(new_name).is_empty():
		return false
	character_name = new_name
	if variant >= 0:
		character_variant = clampi(variant, 0, CharacterFactory.variant_count() - 1)
	if factory_visual_enabled and _visual != null:
		_build_factory_visual()
	return true

## Toggle between the Phase 05 factory visual and the Phase 02
## primitive visual, rebuilding in place. Physics is untouched.
func set_factory_visual_enabled(enabled: bool) -> void:
	factory_visual_enabled = enabled
	if _visual == null:
		return
	if enabled:
		_build_factory_visual()
	else:
		_clear_visual_children()
		_build_primitive_visual()

## "factory" while a CharacterFactory model is the live visual,
## "primitive" while the Phase 02 fallback visual is shown.
func visual_kind() -> String:
	return "factory" if _factory_visual != null else "primitive"

func factory_visual() -> Node3D:
	return _factory_visual

## Current CharacterAnimation state, or "" in primitive mode.
func animation_state() -> String:
	return _anim.state() if _anim != null else ""

## Gameplay event hook (level finish): celebrate briefly.
func celebrate() -> void:
	if _anim != null and _anim.transition_to("celebrate"):
		_celebrate_timer = 0.9

## Original Phase 02 primitive visual (capsule body, sphere head) —
## kept verbatim as the fallback/comparison visual.
func _build_primitive_visual() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42
	capsule.height = 1.25
	body.mesh = capsule
	body.material_override = CollisionManager.make_material(Color(0.95, 0.5, 0.15))
	body.position.y = 0.85
	_visual.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	head.mesh = sphere
	head.material_override = CollisionManager.make_material(Color(1.0, 0.85, 0.6))
	head.position.y = 1.72
	_visual.add_child(head)
	for side in [-1.0, 1.0]:
		var eye := CollisionManager.box_mesh(Vector3(0.09, 0.09, 0.05), Color(0.1, 0.1, 0.15))
		eye.position = Vector3(0.13 * side, 1.78, -0.31)
		_visual.add_child(eye)
		var shoe := CollisionManager.box_mesh(Vector3(0.28, 0.16, 0.45), Color(0.2, 0.35, 0.95))
		shoe.position = Vector3(0.22 * side, 0.08, -0.03)
		shoe.name = "Shoe%d" % int(side)
		_visual.add_child(shoe)

func set_active(value: bool) -> void:
	active = value
	visible = value
	set_physics_process(value)
	if not value:
		velocity = Vector3.ZERO

func reset_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	sliding = false
	_slide_timer = 0.0
	_shape_node.shape = _stand_shape
	_shape_node.position.y = 0.9
	if _anim != null:
		_recover_timer = 0.0
		_celebrate_timer = 0.0
		if _anim.can_transition("run"):
			_anim.transition_to("run")
		elif _anim.can_transition("idle"):
			_anim.transition_to("idle")

func try_jump() -> bool:
	if is_on_floor() and not sliding:
		velocity.y = JUMP_VELOCITY
		return true
	return false

func try_slide() -> bool:
	if is_on_floor() and not sliding:
		sliding = true
		_slide_timer = SLIDE_TIME
		_shape_node.shape = _slide_shape
		_shape_node.position.y = 0.45
		return true
	return false

func _end_slide() -> void:
	sliding = false
	_shape_node.shape = _stand_shape
	_shape_node.position.y = 0.9

func current_speed() -> float:
	return absf(velocity.z)

func _physics_process(delta: float) -> void:
	if not active:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -1.0
	var axis := 0.0
	if input_manager != null:
		axis = input_manager.strafe_axis()
		if input_manager.jump_just_pressed():
			try_jump()
		if input_manager.slide_just_pressed():
			try_slide()
	velocity.x = axis * STRAFE_SPEED
	velocity.z = -RUN_SPEED
	if sliding:
		_slide_timer -= delta
		if _slide_timer <= 0.0:
			_end_slide()
	move_and_slide()
	# Clamp to the course width so the runner cannot leave the world.
	global_position.x = clampf(global_position.x, -9.0, 9.0)
	if global_position.y < -5.0:
		reset_to(Vector3(global_position.x, 0.5, global_position.z + 10.0))
	if _anim != null:
		# Phase 05.1: the Phase 05 state machine poses the factory
		# model from the real movement state computed above.
		_drive_animation(delta)
	elif _visual != null:
		# Phase 02 fallback posing: bob while running, tilt while sliding.
		_bob_phase += delta * RUN_SPEED * 1.4
		if sliding:
			_visual.rotation.x = -1.1
			_visual.position.y = -0.35
		elif not is_on_floor():
			_visual.rotation.x = 0.15
			_visual.position.y = 0.0
		else:
			_visual.rotation.x = 0.0
			_visual.position.y = absf(sin(_bob_phase)) * 0.08
		_visual.rotation.z = -axis * 0.18
	_was_airborne = not is_on_floor()
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider != null and collider.is_in_group("obstacle"):
			bumped_obstacle.emit()
			if _anim != null and _anim.transition_to("recover"):
				_recover_timer = 0.45
			break

## Phase 05.1: derive animation transitions from live gameplay
## state, then let CharacterAnimation pose the factory model.
## States with no live trigger in current gameplay: "sprint" (the
## runner's speed is fixed) and "climb" (no climbable surfaces) —
## both remain in the machine for future mechanics.
func _drive_animation(delta: float) -> void:
	var airborne := not is_on_floor()
	var spd := current_speed()
	if _recover_timer > 0.0:
		_recover_timer -= delta
	elif _celebrate_timer > 0.0:
		_celebrate_timer -= delta
		if _celebrate_timer <= 0.0 and not airborne and not sliding:
			_anim.transition_to("run" if spd > 0.5 else "idle")
	elif airborne:
		if velocity.y > 0.5 and _anim.state() in ["run", "sprint", "idle", "land"]:
			_anim.transition_to("jump")
		elif velocity.y < -0.5 and _anim.state() == "jump":
			_anim.transition_to("fall")
	elif sliding:
		_anim.transition_to("slide")
	else:
		match _anim.state():
			"land":
				if _anim.time_in_state() > 0.15:
					_anim.transition_to("run" if spd > 0.5 else "idle")
			"slide", "recover", "celebrate", "idle", "climb", "sprint":
				_anim.transition_to("run" if spd > 0.5 else "idle")
	_anim.update(delta, spd, airborne, sliding)
