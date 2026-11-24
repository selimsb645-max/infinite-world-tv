class_name CharacterController
extends CharacterBody3D
## Original cartoon runner built from primitives (capsule body, sphere
## head). Auto-runs forward (-Z), strafes with move_left/move_right,
## jumps and slides. Physics via CharacterBody3D.move_and_slide().

signal bumped_obstacle

const RUN_SPEED := 8.0
const STRAFE_SPEED := 7.0
const JUMP_VELOCITY := 9.5
const GRAVITY := 26.0
const SLIDE_TIME := 0.65

var active: bool = false
var sliding: bool = false
var input_manager: InputManager

var _slide_timer: float = 0.0
var _bob_phase: float = 0.0
var _visual: Node3D
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
	# Simple procedural animation: bob while running, tilt while sliding.
	_bob_phase += delta * RUN_SPEED * 1.4
	if _visual != null:
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
			break
