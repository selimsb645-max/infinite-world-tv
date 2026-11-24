extends Node
## CollisionManager - owns layer numbers and builds obstacle/finish colliders from level data.
##
## Layers: 1 = world/ground, 2 = actors (player), 4 = obstacles, 8 = triggers.
## Keeping the numbers in one place is what stops "the car fell through the floor" bugs when
## a new module is added.

const LAYER_WORLD := 1
const LAYER_ACTOR := 2
const LAYER_OBSTACLE := 4
const LAYER_TRIGGER := 8

var obstacle_root: Node3D
var finish_area: Area3D

func build(level: Dictionary, parent: Node3D) -> void:
	clear()
	obstacle_root = Node3D.new()
	obstacle_root.name = "Obstacles"
	parent.add_child(obstacle_root)

	for spec in level.get("obstacles", []):
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_OBSTACLE
		body.collision_mask = 0
		var size: Vector3 = spec["size"]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)

		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.25, 0.30)
		mat.roughness = 0.7
		mi.material_override = mat
		body.add_child(mi)

		body.position = spec["pos"]
		obstacle_root.add_child(body)

	finish_area = Area3D.new()
	finish_area.name = "Finish"
	finish_area.collision_layer = LAYER_TRIGGER
	finish_area.collision_mask = LAYER_ACTOR
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(12.0, 4.0, 2.0)
	fshape.shape = fbox
	finish_area.add_child(fshape)
	var fmesh := MeshInstance3D.new()
	var fboxmesh := BoxMesh.new()
	fboxmesh.size = Vector3(12.0, 0.15, 2.0)
	fmesh.mesh = fboxmesh
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.20, 0.95, 0.45)
	fmat.emission_enabled = true
	fmat.emission = Color(0.20, 0.95, 0.45)
	fmat.emission_energy_multiplier = 1.4
	fmesh.material_override = fmat
	finish_area.add_child(fmesh)
	finish_area.position = level["finish"]
	parent.add_child(finish_area)

func clear() -> void:
	if obstacle_root and is_instance_valid(obstacle_root):
		obstacle_root.queue_free()
	if finish_area and is_instance_valid(finish_area):
		finish_area.queue_free()
	obstacle_root = null
	finish_area = null

func obstacle_count() -> int:
	return obstacle_root.get_child_count() if obstacle_root and is_instance_valid(obstacle_root) else 0
