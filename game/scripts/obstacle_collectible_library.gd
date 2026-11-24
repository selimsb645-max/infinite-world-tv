class_name ObstacleCollectibleLibrary
extends RefCounted
## Phase 05 — obstacle & collectible library.
##
## Original gameplay objects with proper collision and gameplay
## metadata. Obstacles are StaticBody3D in the "obstacle" group on
## the obstacle layer; collectibles are Area3D in the "collectible"
## group on the zone layer, ready for the existing collision setup.
## Every entry carries its metadata dictionary so the level
## generator and validator can reason about it without spawning it.

const OBSTACLES := {
	"moving_platform": {"size": Vector3(3.0, 0.5, 3.0), "color": Color(0.5, 0.7, 0.9), "moves": true, "hazard": false, "solid": true},
	"rotating_barrier": {"size": Vector3(0.4, 1.6, 3.0), "color": Color(0.95, 0.3, 0.3), "moves": true, "hazard": true, "solid": true},
	"jump_gate": {"size": Vector3(3.0, 1.0, 0.4), "color": Color(0.95, 0.6, 0.2), "moves": false, "hazard": false, "solid": true},
	"sliding_barrier": {"size": Vector3(3.0, 1.8, 0.4), "color": Color(0.9, 0.3, 0.6), "moves": true, "hazard": true, "solid": true},
	"falling_platform": {"size": Vector3(2.5, 0.4, 2.5), "color": Color(0.8, 0.7, 0.5), "moves": false, "hazard": true, "solid": true},
	"road_barrier": {"size": Vector3(2.6, 1.1, 0.5), "color": Color(0.95, 0.5, 0.1), "moves": false, "hazard": true, "solid": true},
	"moving_vehicle": {"size": Vector3(1.8, 1.0, 3.2), "color": Color(0.3, 0.6, 0.95), "moves": true, "hazard": true, "solid": true},
	"environment_hazard": {"size": Vector3(2.0, 0.6, 2.0), "color": Color(0.7, 0.2, 0.8), "moves": false, "hazard": true, "solid": false},
}

const COLLECTIBLES := {
	"coin": {"radius": 0.35, "color": Color(1.0, 0.84, 0.25), "score": 10, "effect": "spin"},
	"star": {"radius": 0.45, "color": Color(1.0, 0.9, 0.4), "score": 50, "effect": "sparkle"},
	"energy": {"radius": 0.4, "color": Color(0.3, 0.9, 1.0), "score": 25, "effect": "pulse"},
	"score_bonus": {"radius": 0.5, "color": Color(0.9, 0.4, 0.9), "score": 100, "effect": "burst"},
	"power_up": {"radius": 0.55, "color": Color(0.4, 1.0, 0.5), "score": 0, "effect": "shield"},
}

static func obstacle_names() -> Array[String]:
	var out: Array[String] = []
	for key in OBSTACLES.keys():
		out.append(key)
	return out

static func collectible_names() -> Array[String]:
	var out: Array[String] = []
	for key in COLLECTIBLES.keys():
		out.append(key)
	return out

static func obstacle_metadata(kind: String) -> Dictionary:
	if not OBSTACLES.has(kind):
		return {}
	return OBSTACLES[kind]

static func collectible_metadata(kind: String) -> Dictionary:
	if not COLLECTIBLES.has(kind):
		return {}
	return COLLECTIBLES[kind]

static func build_obstacle(kind: String) -> StaticBody3D:
	var data: Dictionary = obstacle_metadata(kind)
	if data.is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = "Obstacle_%s" % kind
	body.collision_layer = CollisionManager.LAYER_OBSTACLE
	body.collision_mask = 0
	body.add_to_group("obstacle")
	body.set_meta("obstacle", kind)
	body.set_meta("moves", bool(data["moves"]))
	body.set_meta("hazard", bool(data["hazard"]))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = data["size"]
	shape.shape = box
	body.add_child(shape)
	var mesh := CollisionManager.box_mesh(data["size"], data["color"])
	mesh.position.y = float((data["size"] as Vector3).y) * 0.5
	body.add_child(mesh)
	return body

static func build_collectible(kind: String) -> Area3D:
	var data: Dictionary = collectible_metadata(kind)
	if data.is_empty():
		return null
	var area := Area3D.new()
	area.name = "Collectible_%s" % kind
	area.collision_layer = CollisionManager.LAYER_ZONE
	area.collision_mask = 0
	area.add_to_group("collectible")
	area.set_meta("collectible", kind)
	area.set_meta("score", int(data["score"]))
	area.set_meta("effect", str(data["effect"]))
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = float(data["radius"])
	shape.shape = sphere
	area.add_child(shape)
	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = float(data["radius"])
	sphere_mesh.height = float(data["radius"]) * 2.0
	mesh.mesh = sphere_mesh
	mesh.material_override = CollisionManager.make_material(data["color"], 1.2)
	area.add_child(mesh)
	return area
