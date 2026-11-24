extends Node3D
## WorldManager - turns a theme id into a lit, populated environment.
##
## Phase 02 builds geometry from primitives in code: no binary assets, nothing to license,
## and the whole world is reproducible from source. Phase 03 swaps these primitives for
## Blender-authored meshes without changing this module's interface.

const THEMES := {
	"green_valley": {
		"sky_top": Color(0.42, 0.72, 1.0), "sky_horizon": Color(0.82, 0.93, 1.0),
		"ground": Color(0.29, 0.62, 0.31), "fog": Color(0.75, 0.88, 1.0),
		"light_color": Color(1.0, 0.97, 0.88), "light_energy": 1.15,
		"accent": Color(0.16, 0.44, 0.19), "decor": "trees",
	},
	"neon_city": {
		"sky_top": Color(0.05, 0.04, 0.16), "sky_horizon": Color(0.32, 0.10, 0.42),
		"ground": Color(0.13, 0.13, 0.18), "fog": Color(0.18, 0.10, 0.28),
		"light_color": Color(0.72, 0.62, 1.0), "light_energy": 0.85,
		"accent": Color(0.20, 0.90, 0.95), "decor": "towers",
	},
	"desert_world": {
		"sky_top": Color(0.93, 0.66, 0.32), "sky_horizon": Color(1.0, 0.88, 0.66),
		"ground": Color(0.83, 0.68, 0.42), "fog": Color(0.95, 0.83, 0.62),
		"light_color": Color(1.0, 0.87, 0.62), "light_energy": 1.35,
		"accent": Color(0.60, 0.44, 0.22), "decor": "cacti",
	},
	"snow_mountain": {
		"sky_top": Color(0.62, 0.76, 0.90), "sky_horizon": Color(0.92, 0.96, 1.0),
		"ground": Color(0.88, 0.93, 0.98), "fog": Color(0.88, 0.94, 1.0),
		"light_color": Color(0.92, 0.96, 1.0), "light_energy": 1.0,
		"accent": Color(0.55, 0.68, 0.82), "decor": "pines",
	},
	"space_world": {
		"sky_top": Color(0.02, 0.02, 0.08), "sky_horizon": Color(0.10, 0.06, 0.24),
		"ground": Color(0.18, 0.18, 0.24), "fog": Color(0.06, 0.05, 0.14),
		"light_color": Color(0.80, 0.84, 1.0), "light_energy": 0.9,
		"accent": Color(0.55, 0.35, 1.0), "decor": "stars",
	},
}

var theme_id: String = "green_valley"
var _root: Node3D
var _sun: DirectionalLight3D
var _env: WorldEnvironment

func build(id: String, level: Dictionary) -> void:
	clear()
	theme_id = id if THEMES.has(id) else "green_valley"
	var t: Dictionary = THEMES[theme_id]
	_root = Node3D.new()
	_root.name = "Environment"
	add_child(_root)

	_build_sky(t)
	_build_light(t)
	_build_ground(t, level)
	_build_decor(t, level)

func clear() -> void:
	for c in get_children():
		c.queue_free()
	_root = null

func _build_sky(t: Dictionary) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = t["sky_top"]
	sky_mat.sky_horizon_color = t["sky_horizon"]
	sky_mat.ground_bottom_color = t["ground"].darkened(0.4)
	sky_mat.ground_horizon_color = t["sky_horizon"]
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.fog_enabled = true
	env.fog_light_color = t["fog"]
	env.fog_density = 0.006
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env = WorldEnvironment.new()
	_env.name = "WorldEnvironment"
	_env.environment = env
	_root.add_child(_env)

func _build_light(t: Dictionary) -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = t["light_color"]
	_sun.light_energy = t["light_energy"]
	_sun.shadow_enabled = true
	_sun.rotation_degrees = Vector3(-52, -38, 0)
	_root.add_child(_sun)

func _build_ground(t: Dictionary, level: Dictionary) -> void:
	var length: float = float(level.get("length", 200.0))
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# the track must start BEHIND the spawn (z = +25) and end past the finish,
	# otherwise an actor spawned at z > 0 drops into the void
	box.size = Vector3(14.0, 1.0, length + 70.0)
	shape.shape = box
	shape.position = Vector3(0, -0.5, -(length / 2.0) + 25.0)
	body.add_child(shape)

	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, length + 70.0)
	mesh_inst.mesh = plane
	mesh_inst.position = Vector3(0, 0.01, -(length / 2.0) + 25.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = t["ground"]
	mat.roughness = 0.95
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	_root.add_child(body)

	# lane markers give a sense of speed even with flat-shaded primitives
	for i in range(int(length / 20.0)):
		var marker := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.18, 0.02, 6.0)
		marker.mesh = m
		marker.position = Vector3(0, 0.03, -20.0 - i * 20.0)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = t["accent"]
		marker.material_override = mm
		_root.add_child(marker)

func _build_decor(t: Dictionary, level: Dictionary) -> void:
	var length: float = float(level.get("length", 200.0))
	var kind: String = t["decor"]
	var count := 18
	for i in range(count):
		var z := -10.0 - (float(i) / float(count)) * length
		for side in [-1.0, 1.0]:
			var node := MeshInstance3D.new()
			var mesh := Mesh.new()
			var height := 2.4
			var color: Color = t["accent"]
			match kind:
				"trees":
					var cyl := CylinderMesh.new()
					cyl.top_radius = 0.16
					cyl.bottom_radius = 0.22
					cyl.height = 1.6
					mesh = cyl
					height = 1.6
				"pines":
					var cone := CylinderMesh.new()
					cone.top_radius = 0.0
					cone.bottom_radius = 0.7
					cone.height = 2.4
					mesh = cone
					height = 2.4
				"cacti":
					var cyl2 := CylinderMesh.new()
					cyl2.top_radius = 0.28
					cyl2.bottom_radius = 0.32
					cyl2.height = 2.2
					mesh = cyl2
					height = 2.2
				"towers":
					var bx := BoxMesh.new()
					bx.size = Vector3(1.4, 6.0, 1.4)
					mesh = bx
					height = 6.0
				"stars":
					var sp := SphereMesh.new()
					sp.radius = 0.22
					sp.height = 0.44
					mesh = sp
					height = 3.5
			node.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			if kind == "towers":
				mat.emission_enabled = true
				mat.emission = t["accent"]
				mat.emission_energy_multiplier = 1.6
			node.material_override = mat
			node.position = Vector3(side * (5.6 + randf() * 1.2), height * 0.5, z)
			_root.add_child(node)
