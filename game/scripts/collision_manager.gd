class_name CollisionManager
extends Node
## Central place for physics layers, groups and shared body builders.
##
## Layers: 1 = world/ground, 2 = player, 4 = obstacles, 8 = collectibles/zones.
## Groups: "obstacle", "collectible", "finish", "vehicle_pad".

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_OBSTACLE := 4
const LAYER_ZONE := 8

static func make_material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

static func box_mesh(size: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = make_material(color, emission)
	return mi

static func make_static_box(size: Vector3, pos: Vector3, color: Color, group: String = "", emission: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD if group == "" else LAYER_OBSTACLE
	body.collision_mask = 0
	if group != "":
		body.add_to_group(group)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_child(box_mesh(size, color, emission))
	body.position = pos
	return body

static func make_collectible(pos: Vector3, color: Color) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = LAYER_ZONE
	area.collision_mask = LAYER_PLAYER
	area.add_to_group("collectible")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	shape.shape = sphere
	area.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	mi.mesh = mesh
	mi.material_override = make_material(color, 0.7)
	area.add_child(mi)
	area.position = pos
	return area

static func make_zone(size: Vector3, pos: Vector3, group: String) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = LAYER_ZONE
	area.collision_mask = LAYER_PLAYER
	area.add_to_group(group)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	area.position = pos
	return area
