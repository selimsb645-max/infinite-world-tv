class_name EnvironmentAssetLibrary
extends RefCounted
## Phase 05 — environment asset library.
##
## One modular prop set per world (all 8 worlds). Props are original
## primitive builds that match each world's theme colours from
## EnvironmentManager. build_prop() returns a Node3D named
## "Prop_<World>_<Kind>"; solid kinds (platform, road, bridge,
## tunnel) are StaticBody3D with a collision shape so the generator
## can place them as real geometry, decor kinds are plain Node3D.

const WORLDS: Array[String] = [
	"Green Valley", "Neon City", "Desert World", "Snow Mountain",
	"Space World", "Ocean World", "Fantasy Islands", "Futuristic Highway",
]

const PROPS := {
	"Green Valley": ["tree", "rock", "bush", "platform", "bridge", "flower"],
	"Neon City": ["building", "neon_sign", "platform", "bridge", "tunnel", "lamp"],
	"Desert World": ["cactus", "rock", "dune", "platform", "bridge", "oasis_palm"],
	"Snow Mountain": ["pine", "rock", "ice_crystal", "platform", "bridge", "igloo"],
	"Space World": ["crystal", "rock", "antenna", "platform", "bridge", "dome"],
	"Ocean World": ["coral", "rock", "shell", "platform", "bridge", "kelp"],
	"Fantasy Islands": ["mushroom", "crystal", "tree", "platform", "bridge", "candy_tree"],
	"Futuristic Highway": ["pylon", "neon_sign", "platform", "bridge", "tunnel", "holo_ring"],
}

const SOLID_KINDS: Array[String] = ["platform", "road", "bridge", "tunnel"]

static func world_names() -> Array[String]:
	return WORLDS.duplicate()

static func prop_kinds(world: String) -> Array[String]:
	if not PROPS.has(world):
		return []
	var out: Array[String] = []
	for kind in PROPS[world]:
		out.append(kind)
	return out

static func is_solid(kind: String) -> bool:
	return SOLID_KINDS.has(kind)

static func build_prop(world: String, kind: String) -> Node3D:
	if not prop_kinds(world).has(kind):
		return null
	var env := EnvironmentManager.new()
	var theme: Dictionary = env.theme_data(world)
	var decor_color: Color = theme.get("decor_color", Color(0.5, 0.5, 0.5))
	var accent: Color = theme.get("accent_color", Color(0.9, 0.9, 0.9))
	var ground: Color = theme.get("ground_color", Color(0.5, 0.5, 0.5))
	var root: Node3D
	if is_solid(kind):
		var body := StaticBody3D.new()
		body.collision_layer = CollisionManager.LAYER_WORLD
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = _solid_size(kind)
		shape.shape = box
		body.add_child(shape)
		root = body
	else:
		root = Node3D.new()
	root.name = "Prop_%s_%s" % [world.replace(" ", ""), kind]
	root.set_meta("world", world)
	root.set_meta("prop", kind)
	match kind:
		"tree", "pine", "oasis_palm", "candy_tree":
			_add_trunk(root, Color(0.45, 0.3, 0.18), 1.6)
			_add_blob(root, decor_color, Vector3(0, 2.2, 0), 1.1)
			if kind == "candy_tree":
				_add_blob(root, accent, Vector3(0.5, 2.6, 0.2), 0.5)
		"building":
			_add_box(root, decor_color, Vector3(2.2, 6.0, 2.2), Vector3(0, 3.0, 0))
			_add_box(root, accent, Vector3(2.3, 0.4, 2.3), Vector3(0, 6.1, 0), 1.2)
		"rock", "dune":
			_add_blob(root, ground, Vector3(0, 0.4, 0), 0.9)
		"cactus":
			_add_box(root, decor_color, Vector3(0.5, 2.0, 0.5), Vector3(0, 1.0, 0))
			_add_box(root, decor_color, Vector3(1.2, 0.4, 0.4), Vector3(0, 1.2, 0))
		"bush", "flower", "kelp", "coral", "shell", "mushroom":
			_add_blob(root, accent if kind in ["flower", "coral", "shell"] else decor_color,
				Vector3(0, 0.5, 0), 0.6)
			if kind == "mushroom":
				_add_box(root, Color(0.95, 0.9, 0.85), Vector3(0.4, 0.7, 0.4), Vector3(0, 0.35, 0))
		"neon_sign":
			_add_box(root, accent, Vector3(1.8, 0.5, 0.15), Vector3(0, 2.4, 0), 1.6)
			_add_box(root, Color(0.1, 0.1, 0.15), Vector3(0.15, 2.4, 0.15), Vector3(0, 1.2, 0))
		"lamp", "pylon":
			_add_box(root, Color(0.2, 0.2, 0.25), Vector3(0.18, 3.0, 0.18), Vector3(0, 1.5, 0))
			_add_blob(root, accent, Vector3(0, 3.1, 0), 0.3)
		"ice_crystal", "crystal":
			_add_blob(root, accent, Vector3(0, 0.8, 0), 0.7)
			_add_blob(root, decor_color, Vector3(0.5, 0.5, 0.3), 0.45)
		"igloo", "dome":
			_add_blob(root, Color(0.9, 0.95, 1.0), Vector3(0, 0.7, 0), 1.2)
		"antenna":
			_add_box(root, Color(0.3, 0.3, 0.35), Vector3(0.15, 3.4, 0.15), Vector3(0, 1.7, 0))
			_add_blob(root, accent, Vector3(0, 3.5, 0), 0.25)
		"holo_ring":
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.9
			torus.outer_radius = 1.2
			ring.mesh = torus
			ring.material_override = CollisionManager.make_material(accent, 1.4)
			ring.position.y = 2.2
			root.add_child(ring)
		"platform":
			_add_box(root, ground, Vector3(4.0, 0.5, 4.0), Vector3(0, 0.25, 0))
		"bridge":
			_add_box(root, ground, Vector3(3.0, 0.4, 6.0), Vector3(0, 0.2, 0))
			_add_box(root, accent, Vector3(0.2, 0.8, 6.0), Vector3(-1.5, 0.6, 0))
			_add_box(root, accent, Vector3(0.2, 0.8, 6.0), Vector3(1.5, 0.6, 0))
		"tunnel":
			_add_box(root, ground, Vector3(5.0, 0.5, 6.0), Vector3(0, 3.0, 0))
			_add_box(root, ground, Vector3(0.5, 3.0, 6.0), Vector3(-2.5, 1.5, 0))
			_add_box(root, ground, Vector3(0.5, 3.0, 6.0), Vector3(2.5, 1.5, 0))
	return root

static func _solid_size(kind: String) -> Vector3:
	match kind:
		"platform":
			return Vector3(4.0, 0.5, 4.0)
		"bridge":
			return Vector3(3.0, 0.4, 6.0)
		"tunnel":
			return Vector3(5.0, 3.5, 6.0)
	return Vector3(2.0, 1.0, 2.0)

static func _add_box(parent: Node3D, color: Color, size: Vector3, pos: Vector3, emission: float = 0.0) -> void:
	var mi := CollisionManager.box_mesh(size, color, emission)
	mi.position = pos
	parent.add_child(mi)

static func _add_blob(parent: Node3D, color: Color, pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mi.mesh = sphere
	mi.material_override = CollisionManager.make_material(color)
	mi.position = pos
	parent.add_child(mi)

static func _add_trunk(parent: Node3D, color: Color, height: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.28
	cyl.height = height
	mi.mesh = cyl
	mi.material_override = CollisionManager.make_material(color)
	mi.position.y = height * 0.5
	parent.add_child(mi)
