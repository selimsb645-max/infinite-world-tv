extends CharacterBody3D
## VehicleController - racer mode: accelerate, brake, steer, collide.
##
## Deliberately CharacterBody3D, not VehicleBody3D. VehicleBody3D's tyre model is realistic
## but hard to make deterministic and hard to assert in a test; this arcade model is stable at
## 60 Hz, never flips, and gives identical results from identical inputs, which Phase 03's
## pre-rendering depends on. Documented as a Phase 02 tradeoff, not an oversight.

signal bumped

const MAX_SPEED := 26.0
const REVERSE_SPEED := -6.0
const ACCEL := 14.0
const BRAKE := 26.0
const STEER_RATE := 2.4
const LANE_LIMIT := 4.2
const GRAVITY := 26.0

var active := false
var speed := 0.0
var distance_travelled := 0.0
var _visual: Node3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.5
	_build_visual()

func _build_visual() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 0.9, 2.6)
	shape.shape = box
	shape.position.y = 0.45
	add_child(shape)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var chassis := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.5, 0.55, 2.5)
	chassis.mesh = cm
	chassis.position.y = 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.52, 0.95)
	mat.roughness = 0.35
	mat.metallic = 0.25
	chassis.material_override = mat
	_visual.add_child(chassis)

	var cabin := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(1.1, 0.45, 1.1)
	cabin.mesh = cb
	cabin.position = Vector3(0, 0.9, -0.1)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.82, 0.92, 1.0)
	cmat.metallic = 0.6
	cmat.roughness = 0.15
	cabin.material_override = cmat
	_visual.add_child(cabin)

	for corner in [Vector3(-0.7, 0.22, -0.85), Vector3(0.7, 0.22, -0.85), Vector3(-0.7, 0.22, 0.85), Vector3(0.7, 0.22, 0.85)]:
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.32
		wm.bottom_radius = 0.32
		wm.height = 0.22
		wheel.mesh = wm
		wheel.position = corner
		wheel.rotation_degrees = Vector3(0, 0, 90)
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.10, 0.10, 0.12)
		wheel.material_override = wmat
		_visual.add_child(wheel)

func step(intent: Dictionary, delta: float) -> void:
	if not active:
		return

	var throttle: float = float(intent.get("accelerate", 0.0))
	if throttle > 0.01:
		speed = move_toward(speed, MAX_SPEED, ACCEL * delta)
	elif throttle < -0.01:
		speed = move_toward(speed, REVERSE_SPEED, BRAKE * delta)
	else:
		speed = move_toward(speed, 0.0, ACCEL * 0.6 * delta)

	var steer: float = float(intent.get("steer", 0.0))
	rotation.y -= steer * STEER_RATE * delta * clampf(absf(speed) / MAX_SPEED, 0.25, 1.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var forward := -transform.basis.z * speed
	velocity.x = forward.x
	velocity.z = forward.z
	position.x = clampf(position.x, -LANE_LIMIT, LANE_LIMIT)

	var before := position
	move_and_slide()
	distance_travelled += (position - before).length()

	# hitting a wall bleeds speed instead of stopping dead: keeps the stream watchable
	for i in range(get_slide_collision_count()):
		var c := get_slide_collision(i)
		if c.get_normal().y < 0.6:
			speed *= 0.55
			bumped.emit()
			break

func reset_at(pos: Vector3) -> void:
	position = pos
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	speed = 0.0
