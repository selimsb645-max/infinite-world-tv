class_name VehicleController
extends CharacterBody3D
## Arcade car on CharacterBody3D: accelerate / brake / steer with
## speed-sensitive steering and simple drag. The physics body is
## always the authority; the visual only follows it.
##
## Phase 05.1: the visual is a VehicleFactory model (Phase 05)
## driven by VehicleAnimation (wheel spin from real speed, front
## steering from real steer input, brake dive / accel squat), and
## the collision box is sized from the factory's collision_spec().
## The original Phase 02 primitive car remains available via
## factory_visual_enabled = false (tools/tests fallback).

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

## Phase 05.1: which factory vehicle this controller shows/drives.
var vehicle_kind: String = "SportsCar"
## Phase 05.1: true = Phase 05 factory visual; false = Phase 02
## primitive visual (fallback / comparison mode).
var factory_visual_enabled: bool = true

var _visual: Node3D
var _factory_visual: Node3D
var _anim: VehicleAnimation
var _shape_node: CollisionShape3D
var _wheels: Array[MeshInstance3D] = []

func _init() -> void:
	collision_layer = CollisionManager.LAYER_PLAYER
	collision_mask = CollisionManager.LAYER_WORLD | CollisionManager.LAYER_OBSTACLE
	_shape_node = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 0.9, 3.4)
	_shape_node.shape = box
	_shape_node.position.y = 0.55
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
## container, bind VehicleAnimation to it and size the physics box
## from the factory collision spec.
func _build_factory_visual() -> void:
	_clear_visual_children()
	_factory_visual = VehicleFactory.build(vehicle_kind)
	if _factory_visual == null:
		vehicle_kind = "SportsCar"
		_factory_visual = VehicleFactory.build(vehicle_kind)
	_visual.add_child(_factory_visual)
	_anim = VehicleAnimation.new(_factory_visual)
	_apply_factory_collision()

func _clear_visual_children() -> void:
	if _visual == null:
		return
	for child in _visual.get_children():
		_visual.remove_child(child)
		child.queue_free()
	_factory_visual = null
	_anim = null
	_wheels.clear()

func _apply_factory_collision() -> void:
	var spec := VehicleFactory.collision_spec(vehicle_kind)
	if spec.is_empty():
		return
	var size: Vector3 = spec["size"]
	var box := _shape_node.shape as BoxShape3D
	if box != null:
		box.size = size
	_shape_node.position.y = size.y * 0.5 + 0.02

func _apply_primitive_collision() -> void:
	var box := _shape_node.shape as BoxShape3D
	if box != null:
		box.size = Vector3(1.9, 0.9, 3.4)
	_shape_node.position.y = 0.55

## Switch the live vehicle to another factory kind. Returns false
## (and changes nothing) for an unknown kind.
func set_vehicle_kind(new_kind: String) -> bool:
	if VehicleFactory.spec(new_kind).is_empty():
		return false
	vehicle_kind = new_kind
	if factory_visual_enabled and _visual != null:
		_build_factory_visual()
	return true

## Toggle between the Phase 05 factory visual + collision spec and
## the Phase 02 primitive visual + original collision box.
func set_factory_visual_enabled(enabled: bool) -> void:
	factory_visual_enabled = enabled
	if _visual == null:
		return
	if enabled:
		_build_factory_visual()
	else:
		_clear_visual_children()
		_apply_primitive_collision()
		_build_primitive_visual()

## "factory" while a VehicleFactory model is the live visual,
## "primitive" while the Phase 02 fallback visual is shown.
func visual_kind() -> String:
	return "factory" if _factory_visual != null else "primitive"

func factory_visual() -> Node3D:
	return _factory_visual

## The four factory wheel pivots (WheelFL/FR/RL/RR), factory mode only.
func wheel_pivots() -> Array[Node3D]:
	return _anim.wheels() if _anim != null else []

## Accumulated wheel spin angle from VehicleAnimation (factory mode).
func wheel_spin() -> float:
	return _anim.wheel_spin() if _anim != null else 0.0

## Original Phase 02 primitive car — kept verbatim as the
## fallback/comparison visual.
func _build_primitive_visual() -> void:
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
	if _anim != null:
		# Phase 05.1: VehicleAnimation spins the factory wheels from
		# the real speed, steers the front pivots from the real steer
		# input and dives/squats the body under braking/acceleration.
		var braking := throttle < 0.0 and speed > 0.5
		_anim.update(delta, speed, steer, braking)
	else:
		# Phase 02 fallback posing.
		for wheel in _wheels:
			wheel.rotate_x(speed * delta / 0.38)
		if _visual != null:
			_visual.rotation.z = -steer * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0) * 0.06
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider != null and collider.is_in_group("obstacle"):
			speed *= 0.55
			bumped_obstacle.emit()
			if _anim != null:
				_anim.on_collision(1.0)
			break
