class_name CharacterFactory
extends RefCounted
## Phase 05 — original character creation.
##
## Four original, family-friendly cartoon characters built only from
## primitives (no external meshes, no copied designs). Each character
## has a distinct silhouette, its own accessory, consistent proportions
## and three colour variants. Parts are modular: the returned Node3D
## has named children (Body, Head, Accessory, ArmL, ArmR, LegL, LegR)
## so the animation state machine and later tools can pose them.
##
##   Pip  — small, round, red cap, the default runner.
##   Zara — tall and slim, scarf, long stride.
##   Milo — wide and sturdy, backpack, heavy boots.
##   Nova — medium, antenna + star badge, springy.
##
## build() never touches gameplay: it only builds the visual.

const CHARACTERS := {
	"Pip": {
		"height": 1.5, "body_radius": 0.42, "body_color": Color(0.95, 0.5, 0.15),
		"skin_color": Color(1.0, 0.85, 0.6), "accessory": "cap",
		"accessory_color": Color(0.85, 0.15, 0.2),
	},
	"Zara": {
		"height": 1.9, "body_radius": 0.32, "body_color": Color(0.35, 0.55, 0.95),
		"skin_color": Color(0.85, 0.65, 0.45), "accessory": "scarf",
		"accessory_color": Color(0.95, 0.75, 0.2),
	},
	"Milo": {
		"height": 1.65, "body_radius": 0.52, "body_color": Color(0.25, 0.6, 0.3),
		"skin_color": Color(0.95, 0.8, 0.6), "accessory": "backpack",
		"accessory_color": Color(0.6, 0.4, 0.15),
	},
	"Nova": {
		"height": 1.7, "body_radius": 0.38, "body_color": Color(0.65, 0.35, 0.85),
		"skin_color": Color(1.0, 0.85, 0.65), "accessory": "antenna",
		"accessory_color": Color(1.0, 0.85, 0.2),
	},
}

## Colour variants: each character can be recoloured without changing
## its silhouette. Variant 0 is the default look.
const VARIANTS: Array[Dictionary] = [
	{"body": Color(1, 1, 1), "accent": Color(1, 1, 1), "name": "default"},
	{"body": Color(0.7, 0.9, 1.0), "accent": Color(1.0, 0.6, 0.6), "name": "cool"},
	{"body": Color(1.0, 0.9, 0.6), "accent": Color(0.6, 1.0, 0.7), "name": "warm"},
]

static func character_names() -> Array[String]:
	var out: Array[String] = []
	for key in CHARACTERS.keys():
		out.append(key)
	return out

static func variant_count() -> int:
	return VARIANTS.size()

static func spec(character_name: String) -> Dictionary:
	if not CHARACTERS.has(character_name):
		return {}
	return CHARACTERS[character_name]

static func build(character_name: String, variant: int = 0) -> Node3D:
	var data: Dictionary = spec(character_name)
	if data.is_empty():
		return null
	variant = clampi(variant, 0, VARIANTS.size() - 1)
	var tint: Dictionary = VARIANTS[variant]
	var body_color: Color = (data["body_color"] as Color) * (tint["body"] as Color)
	var accent_color: Color = (data["accessory_color"] as Color) * (tint["accent"] as Color)
	var h: float = float(data["height"])
	var r: float = float(data["body_radius"])

	var root := Node3D.new()
	root.name = "Character_%s" % character_name
	root.set_meta("character", character_name)
	root.set_meta("variant", variant)
	root.set_meta("height", h)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = r
	capsule.height = h * 0.62
	body.mesh = capsule
	body.material_override = CollisionManager.make_material(body_color)
	body.position.y = h * 0.45
	root.add_child(body)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var sphere := SphereMesh.new()
	sphere.radius = h * 0.2
	sphere.height = h * 0.4
	head.mesh = sphere
	head.material_override = CollisionManager.make_material(data["skin_color"])
	head.position.y = h * 0.88
	root.add_child(head)

	var accessory := _build_accessory(str(data["accessory"]), accent_color, h, r)
	accessory.name = "Accessory"
	root.add_child(accessory)

	for side in ["L", "R"]:
		var arm := MeshInstance3D.new()
		arm.name = "Arm" + side
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = r * 0.28
		arm_mesh.height = h * 0.32
		arm.mesh = arm_mesh
		arm.material_override = CollisionManager.make_material(body_color)
		arm.position = Vector3((r + 0.12) * (1.0 if side == "R" else -1.0), h * 0.55, 0.0)
		root.add_child(arm)
		var leg := MeshInstance3D.new()
		leg.name = "Leg" + side
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = r * 0.32
		leg_mesh.height = h * 0.28
		leg.mesh = leg_mesh
		leg.material_override = CollisionManager.make_material(Color(0.25, 0.25, 0.35))
		leg.position = Vector3(r * 0.45 * (1.0 if side == "R" else -1.0), h * 0.14, 0.0)
		root.add_child(leg)
	return root

static func _build_accessory(kind: String, color: Color, h: float, r: float) -> Node3D:
	var node := Node3D.new()
	node.position.y = h * 1.02
	match kind:
		"cap":
			var cap := MeshInstance3D.new()
			var dome := SphereMesh.new()
			dome.radius = h * 0.21
			dome.height = h * 0.2
			cap.mesh = dome
			cap.material_override = CollisionManager.make_material(color)
			node.add_child(cap)
			var brim := MeshInstance3D.new()
			var brim_mesh := BoxMesh.new()
			brim_mesh.size = Vector3(h * 0.34, 0.04, h * 0.2)
			brim.mesh = brim_mesh
			brim.material_override = CollisionManager.make_material(color)
			brim.position = Vector3(0, -0.02, -h * 0.2)
			node.add_child(brim)
		"scarf":
			var scarf := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = h * 0.14
			torus.outer_radius = h * 0.2
			scarf.mesh = torus
			scarf.material_override = CollisionManager.make_material(color)
			scarf.rotation.x = PI / 2.0
			node.add_child(scarf)
		"backpack":
			var pack := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(r * 1.1, h * 0.4, r * 0.6)
			pack.mesh = box
			pack.material_override = CollisionManager.make_material(color)
			pack.position = Vector3(0, -h * 0.35, r + 0.18)
			node.add_child(pack)
		"antenna":
			var rod := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.03
			cyl.bottom_radius = 0.03
			cyl.height = h * 0.3
			rod.mesh = cyl
			rod.material_override = CollisionManager.make_material(Color(0.3, 0.3, 0.35))
			rod.position.y = h * 0.12
			node.add_child(rod)
			var tip := MeshInstance3D.new()
			var tip_mesh := SphereMesh.new()
			tip_mesh.radius = 0.07
			tip_mesh.height = 0.14
			tip.mesh = tip_mesh
			tip.material_override = CollisionManager.make_material(color, 1.5)
			tip.position.y = h * 0.28
			node.add_child(tip)
	return node
