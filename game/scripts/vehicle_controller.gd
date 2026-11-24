class_name VehicleController
extends CharacterBody3D
## Original cartoon car built from primitives (rounded box body, cabin,
## cylinder wheels). Arcade driving on CharacterBody3D: accelerate /
## brake / steer with speed-sensitive steering and simple drag.

signal bumped_obstacle

const MAX_SPEED := 24.0
const MAX_REVERSE := 6.0
const ACCELERATION := 11.0
const BRAKE_FORCE := 20.0
const DRAG := 2.2
const STEER_RATE := 1.5
const GRAVITY := 26.0

var active: bool = false
var speed: float = 0.0
var input_manager: InputManager

var _visual: Node3D
var _wheels: Array[MeshInstance3D] = []

func _init() -> void:
	collision_layer = CollisionManager.LAYER_PLAYER
	collision_mask = CollisionManager.LAYER_WORLD | CollisionManager.LAYER_OBSTACLE
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 0.9, 3.4)
	shape_node.shape = box
	shape_node.position.y = 0.55
	add_child(shape_node)
	_build_visual()

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var body := CollisionManager.box_mesh(Vector3(1.9, 0.65, 3.4), Color(0.15, 0.55, 0.95))
	body.position.y = 0.55
	_visual.add_child(body)
	var cabin := CollisionManager.box_mesh(Vector3(1.6, 0.6, 1.7), Color(0.65, 0.85, 1.0))
	cabin.position = Vector3(0, 1.15, 0.25)
	_visual.add_child(cabin)
	var stripe := CollisionManager.box_mesh(Vector3(1.94, 0.18, 3.44), Color(1.0, 0.8, 0.2))
	stripe.position.y = 0.32
	_visual.add_child(stripe)
	for x in [-0.95, 0.95]:
		for z in [-1.15, 1.15]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.38
			cyl.bottom_radius = 0.38
			cyl.height = 0.25
			wheel.mesh = cyl
			wheel.material_override = CollisionManager.make_material(Color(0.08, 0.08, 0.1))
			wheel.rotation.z = PI / 2.0
			wheel.position = Vector3(x, 0.38, z)
			_visual.add_child(wheel)
			_wheels.append(wheel)

func set_active(value: bool) -> void:
	active = value
	visible = value
	set_physics_process(value)
	if not value:
		speed = 0.0
		velocity = Vector3.ZERO

func reset_to(pos: Vector3) -> void:
	global_position = pos
	rotation = Vector3.ZERO
	speed = 0.0
	velocity = Vector3.ZERO

func current_speed() -> float:
	return absf(speed)

func _physics_process(delta: float) -> void:
	if not active:
		return
	var throttle := 0.0
	var steer := 0.0
	if input_manager != null:
		throttle = input_manager.throttle_axis()
		steer = input_manager.strafe_axis()
	if throttle > 0.0:
		speed += ACCELERATION * throttle * delta
	elif throttle < 0.0:
		if speed > 0.5:
			speed -= BRAKE_FORCE * -throttle * delta
		else:
			speed += ACCELERATION * 0.5 * throttle * delta
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	speed = clampf(speed, -MAX_REVERSE, MAX_SPEED)
	if absf(speed) > 0.05:
		var steer_amount := steer * STEER_RATE * clampf(absf(speed) / 8.0, 0.25, 1.0)
		rotate_y(-steer_amount * delta * signf(speed))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -1.0
	var forward := -global_transform.basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	move_and_slide()
	global_position.x = clampf(global_position.x, -11.0, 11.0)
	if global_position.y < -5.0:
		reset_to(Vector3(global_position.x, 0.5, global_position.z + 10.0))
	for wheel in _wheels:
		wheel.rotate_x(speed * delta / 0.38)
	if _visual != null:
		_visual.rotation.z = -steer * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0) * 0.06
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider != null and collider.is_in_group("obstacle"):
			speed *= 0.55
			bumped_obstacle.emit()
			break
