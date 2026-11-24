class_name VehicleFactory
extends RefCounted
## Phase 05 — original vehicle collection.
##
## Five original cartoon vehicles, built only from primitives — no
## real automotive logos or trademarked designs. Every vehicle has a
## unique silhouette, a steering front axle, four spinning wheel
## pivots (WheelFL/FR/RL/RR) and a collision spec. The returned
## Node3D is named "Vehicle_<Kind>" and carries metadata so the
## animation system and the registry can inspect it without guessing.

const VEHICLES := {
	"SportsCar": {
		"body_color": Color(0.9, 0.15, 0.2), "length": 3.4, "width": 1.7,
		"height": 0.85, "wheel_radius": 0.36, "spoiler": true, "cabin": true,
	},
	"OffRoad": {
		"body_color": Color(0.85, 0.55, 0.15), "length": 3.2, "width": 1.9,
		"height": 1.15, "wheel_radius": 0.48, "spoiler": false, "cabin": true,
	},
	"Futuristic": {
		"body_color": Color(0.3, 0.85, 0.9), "length": 3.8, "width": 1.8,
		"height": 0.7, "wheel_radius": 0.34, "spoiler": false, "cabin": false,
	},
	"Compact": {
		"body_color": Color(0.95, 0.8, 0.2), "length": 2.5, "width": 1.5,
		"height": 1.0, "wheel_radius": 0.32, "spoiler": false, "cabin": true,
	},
	"Fantasy": {
		"body_color": Color(0.75, 0.4, 0.9), "length": 3.1, "width": 1.8,
		"height": 1.0, "wheel_radius": 0.4, "spoiler": true, "cabin": true,
	},
}

static func vehicle_names() -> Array[String]:
	var out: Array[String] = []
	for key in VEHICLES.keys():
		out.append(key)
	return out

static func spec(vehicle_name: String) -> Dictionary:
	if not VEHICLES.has(vehicle_name):
		return {}
	return VEHICLES[vehicle_name]

## Collision + physics metadata for a vehicle kind. Used by the
## registry validator and by any controller that spawns the vehicle.
static func collision_spec(vehicle_name: String) -> Dictionary:
	var data: Dictionary = spec(vehicle_name)
	if data.is_empty():
		return {}
	return {
		"size": Vector3(float(data["width"]), float(data["height"]), float(data["length"])),
		"wheel_radius": float(data["wheel_radius"]),
		"wheelbase": float(data["length"]) * 0.62,
		"track": float(data["width"]) * 0.82,
	}

static func build(vehicle_name: String) -> Node3D:
	var data: Dictionary = spec(vehicle_name)
	if data.is_empty():
		return null
	var length: float = float(data["length"])
	var width: float = float(data["width"])
	var height: float = float(data["height"])
	var wheel_r: float = float(data["wheel_radius"])
	var color: Color = data["body_color"]

	var root := Node3D.new()
	root.name = "Vehicle_%s" % vehicle_name
	root.set_meta("vehicle", vehicle_name)
	root.set_meta("length", length)
	root.set_meta("wheel_radius", wheel_r)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(width, height * 0.55, length)
	body.mesh = body_mesh
	body.material_override = CollisionManager.make_material(color)
	body.position.y = wheel_r + height * 0.28
	root.add_child(body)

	if bool(data["cabin"]):
		var cabin := MeshInstance3D.new()
		cabin.name = "Cabin"
		var cabin_mesh := BoxMesh.new()
		cabin_mesh.size = Vector3(width * 0.72, height * 0.5, length * 0.42)
		cabin.mesh = cabin_mesh
		cabin.material_override = CollisionManager.make_material(Color(0.65, 0.85, 0.95), 0.25)
		cabin.position = Vector3(0, wheel_r + height * 0.75, -length * 0.05)
		root.add_child(cabin)

	if bool(data["spoiler"]):
		var spoiler := MeshInstance3D.new()
		spoiler.name = "Spoiler"
		var spoiler_mesh := BoxMesh.new()
		spoiler_mesh.size = Vector3(width * 0.95, 0.07, 0.4)
		spoiler.mesh = spoiler_mesh
		spoiler.material_override = CollisionManager.make_material(Color(0.15, 0.15, 0.2))
		spoiler.position = Vector3(0, wheel_r + height * 0.95, length * 0.46)
		root.add_child(spoiler)

	var wheelbase: float = length * 0.62
	var track: float = width * 0.82
	for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var pivot := Node3D.new()
		pivot.name = wheel_name
		var front: bool = wheel_name.ends_with("FL") or wheel_name.ends_with("FR")
		var right: bool = wheel_name.ends_with("FR") or wheel_name.ends_with("RR")
		pivot.position = Vector3(
			track * 0.5 * (1.0 if right else -1.0),
			wheel_r,
			-wheelbase * 0.5 * (1.0 if front else -1.0))
		var wheel := MeshInstance3D.new()
		wheel.name = "Tire"
		var tire := CylinderMesh.new()
		tire.top_radius = wheel_r
		tire.bottom_radius = wheel_r
		tire.height = 0.24
		wheel.mesh = tire
		wheel.rotation.z = PI / 2.0
		wheel.material_override = CollisionManager.make_material(Color(0.12, 0.12, 0.14))
		pivot.add_child(wheel)
		var hub := MeshInstance3D.new()
		hub.name = "Hub"
		var hub_mesh := CylinderMesh.new()
		hub_mesh.top_radius = wheel_r * 0.5
		hub_mesh.bottom_radius = wheel_r * 0.5
		hub_mesh.height = 0.26
		hub.mesh = hub_mesh
		hub.rotation.z = PI / 2.0
		hub.material_override = CollisionManager.make_material(Color(0.85, 0.85, 0.9))
		pivot.add_child(hub)
		root.add_child(pivot)
	return root
