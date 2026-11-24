extends CharacterBody3D
## CharacterController - runner mode: run forward, jump, slide, strafe, land.
##
## Physics is explicit (no AnimationTree yet) so behaviour is testable: a headless test can
## assert jump height and slide duration numerically instead of eyeballing a clip.

signal jumped
signal slid
signal landed

const RUN_SPEED := 9.0
const STRAFE_SPEED := 6.5
const ACCEL := 24.0
const GRAVITY := 26.0
const JUMP_VELOCITY := 9.2
const SLIDE_TIME := 0.55
const SLIDE_SPEED_MULT := 1.35
const LANE_LIMIT := 4.6

var active := true
var sliding := false
var slide_timer := 0.0
var was_on_floor := true
var distance_travelled := 0.0

var _visual: Node3D
var _body_mesh: MeshInstance3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	_build_visual()
	floor_snap_length = 0.4

func _build_visual() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.6
	shape.shape = cap
	add_child(shape)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	_body_mesh = MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.36
	body.height = 1.5
	_body_mesh.mesh = body
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.25)
	mat.roughness = 0.55
	_body_mesh.material_override = mat
	_visual.add_child(_body_mesh)

	# head + eyes: enough silhouette to read as a cartoon character at a distance
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.3
	sph.height = 0.6
	head.mesh = sph
	head.position = Vector3(0, 0.72, 0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.82, 0.62)
	head.material_override = hmat
	_visual.add_child(head)

	for x in [-0.11, 0.11]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.055
		es.height = 0.11
		eye.mesh = es
		eye.position = Vector3(x, 0.78, -0.26)
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(0.08, 0.08, 0.12)
		eye.material_override = emat
		_visual.add_child(eye)

func step(intent: Dictionary, delta: float) -> void:
	if not active:
		return

	# vertical
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif intent.get("jump", false):
		velocity.y = JUMP_VELOCITY
		jumped.emit()

	# slide
	var want_slide: bool = intent.get("slide", false)
	if want_slide and is_on_floor() and not sliding:
		sliding = true
		slide_timer = SLIDE_TIME
		slid.emit()
	if sliding:
		slide_timer -= delta
		if slide_timer <= 0.0:
			sliding = false
	if _visual:
		var target_scale := Vector3(1.0, 0.45 if sliding else 1.0, 1.0)
		_visual.scale = _visual.scale.lerp(target_scale, min(1.0, delta * 14.0))

	# horizontal: forward is -Z, strafe is X, bounded to the lane
	var speed := RUN_SPEED * (SLIDE_SPEED_MULT if sliding else 1.0)
	var strafe: float = float(intent.get("move", 0.0)) * STRAFE_SPEED
	velocity.z = -speed
	velocity.x = move_toward(velocity.x, strafe, ACCEL * delta)
	position.x = clampf(position.x, -LANE_LIMIT, LANE_LIMIT)

	var before := position
	move_and_slide()
	distance_travelled += (position - before).length()

	if is_on_floor() and not was_on_floor:
		landed.emit()
	was_on_floor = is_on_floor()

func reset_at(pos: Vector3) -> void:
	position = pos
	velocity = Vector3.ZERO
	sliding = false
	slide_timer = 0.0
	was_on_floor = true
