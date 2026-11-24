class_name WorldManager
extends Node3D
## Builds and tears down level geometry from LevelManager data:
## ground + path, decorations (style depends on the theme), obstacles,
## collectibles, a vehicle pad (mode-switch trigger) and a finish zone.
## Everything is original primitive geometry created in code.

signal collectible_picked(area: Area3D)
signal finish_reached
signal vehicle_pad_entered

var _root: Node3D
var _collectibles: Array[Area3D] = []
var _spin_phase: float = 0.0
var _active_body: Node3D

# Phase 03: pooled high-churn nodes (obstacles, collectibles) and
# moving-platform animation state. Pools persist across level builds.
var _obstacle_pool := ObjectPool.new()
var _collectible_pool := ObjectPool.new()
var _active_obstacles: Array[StaticBody3D] = []
var _moving_platforms: Array[Dictionary] = []

func pool_stats() -> Dictionary:
	return {
		"obstacle_pool_size": _obstacle_pool.size(),
		"collectible_pool_size": _collectible_pool.size(),
		"obstacles_reused": _obstacle_pool.reused_count,
		"collectibles_reused": _collectible_pool.reused_count,
		"obstacles_created": _obstacle_pool.created_count,
		"collectibles_created": _collectible_pool.created_count,
	}

func _physics_process(_delta: float) -> void:
	if _moving_platforms.is_empty():
		return
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	for mp in _moving_platforms:
		var body: AnimatableBody3D = mp["body"]
		if is_instance_valid(body):
			body.position.x = float(mp["base_x"]) + sin(t * float(mp["speed"]) + float(mp["phase"])) * float(mp["range"])

## Only the currently controlled body may trigger zones/collectibles.
## The inactive controller is still a physics body in the world, and a
## freshly built area can also report a stale overlap for one step —
## both must never score points or finish a level.
func set_active_body(body: Node3D) -> void:
	_active_body = body

func _is_active(body: Node3D) -> bool:
	return _active_body != null and body == _active_body

func _process(delta: float) -> void:
	_spin_phase += delta * 2.5
	for area in _collectibles:
		if is_instance_valid(area):
			area.rotation.y = _spin_phase
			area.position.y = area.get_meta("base_y") + sin(_spin_phase * 1.4) * 0.15

func clear() -> void:
	# Return pooled nodes to their pools BEFORE the old root is freed.
	for ob in _active_obstacles:
		if is_instance_valid(ob):
			_obstacle_pool.release(ob, str(ob.get_meta("pool_key", "block")))
	_active_obstacles.clear()
	for area in _collectibles:
		if is_instance_valid(area):
			_collectible_pool.release(area, "collectible")
	_collectibles.clear()
	_moving_platforms.clear()
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "LevelRoot"
	add_child(_root)

func build(level: Dictionary, theme: Dictionary) -> void:
	clear()
	var length: float = level["length"]
	var width: float = level["width"]
	# Ground + path: generated levels supply explicit strips (which
	# can leave platform-spanned gaps, narrow bridges, lane shifts);
	# handcrafted Phase 02 levels use the original single slab.
	if level.has("ground_strips") and not (level["ground_strips"] as Array).is_empty():
		for strip in level["ground_strips"]:
			_root.add_child(CollisionManager.make_static_box(
				Vector3(float(strip["w"]), 1.0, float(strip["len"])),
				Vector3(float(strip["x"]), -0.5, float(strip["z_center"])), theme["ground_color"]))
		for strip in level["path_strips"]:
			var p := CollisionManager.box_mesh(
				Vector3(float(strip["w"]), 0.12, float(strip["len"])), theme["path_color"])
			p.position = Vector3(float(strip["x"]), 0.06, float(strip["z_center"]))
			_root.add_child(p)
	else:
		var ground := CollisionManager.make_static_box(
			Vector3(width + 30.0, 1.0, length + 30.0),
			Vector3(0, -0.5, -length / 2.0 + 5.0), theme["ground_color"])
		_root.add_child(ground)
		var path := CollisionManager.box_mesh(
			Vector3(width, 0.12, length + 10.0), theme["path_color"])
		path.position = Vector3(0, 0.06, -length / 2.0 + 5.0)
		_root.add_child(path)
	_build_decor(level, theme, length, width)
	for ob in level["obstacles"]:
		var body := _make_obstacle(ob, theme)
		_root.add_child(body)
		_active_obstacles.append(body)
	for pos in level["collectibles"]:
		var area := _make_collectible(pos, theme)
		_root.add_child(area)
		_collectibles.append(area)
	_build_generated_structures(level, theme, width)
	# Vehicle pad: stepping/driving here offers the mode switch.
	var pad := CollisionManager.make_zone(
		Vector3(6.0, 1.0, 6.0), Vector3(4.5, 0.5, level["vehicle_pad_z"]), "vehicle_pad")
	var pad_visual := CollisionManager.box_mesh(
		Vector3(6.0, 0.15, 6.0), theme["accent_color"], 0.4)
	pad_visual.position = Vector3(4.5, 0.08, level["vehicle_pad_z"])
	_root.add_child(pad_visual)
	pad.body_entered.connect(_on_pad_body)
	_root.add_child(pad)
	# Finish zone at the end of the course.
	var finish := CollisionManager.make_zone(
		Vector3(width, 4.0, 2.0), Vector3(0, 2.0, -length + 2.0), "finish")
	var banner := CollisionManager.box_mesh(
		Vector3(width, 0.6, 0.4), theme["accent_color"], 0.5)
	banner.position = Vector3(0, 3.6, -length + 2.0)
	_root.add_child(banner)
	finish.body_entered.connect(_on_finish_body)
	_root.add_child(finish)

func _build_decor(level: Dictionary, theme: Dictionary, length: float, width: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = level["seed"]
	var style: String = theme["decor"]
	for i in level["decor_count"]:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x: float = side * (width / 2.0 + rng.randf_range(2.5, 9.0))
		var z: float = rng.randf_range(-length + 4.0, 4.0)
		var decor := _make_decor(style, theme, rng)
		decor.position = Vector3(x, 0.0, z)
		_root.add_child(decor)

func _make_decor(style: String, theme: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var color: Color = theme["decor_color"]
	var accent: Color = theme["accent_color"]
	match style:
		"trees", "pines":
			var trunk := CollisionManager.box_mesh(Vector3(0.5, 1.6, 0.5), accent)
			trunk.position.y = 0.8
			root.add_child(trunk)
			var top := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.5
			cone.height = 3.4
			top.mesh = cone
			top.material_override = CollisionManager.make_material(color)
			top.position.y = 3.2
			root.add_child(top)
		"buildings":
			var h := rng.randf_range(3.0, 9.0)
			var tower := CollisionManager.box_mesh(Vector3(2.6, h, 2.6), Color(0.16, 0.16, 0.28), 0.0)
			tower.position.y = h / 2.0
			root.add_child(tower)
			var sign := CollisionManager.box_mesh(Vector3(2.7, 0.5, 2.7), color, 1.2)
			sign.position.y = h + 0.25
			root.add_child(sign)
		"cacti":
			var body := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.35
			cyl.bottom_radius = 0.35
			cyl.height = 2.4
			body.mesh = cyl
			body.material_override = CollisionManager.make_material(color)
			body.position.y = 1.2
			root.add_child(body)
			var arm := CollisionManager.box_mesh(Vector3(1.2, 0.4, 0.4), color)
			arm.position = Vector3(0.6, 1.6, 0)
			root.add_child(arm)
		"crystals":
			var crystal := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(1.1, rng.randf_range(2.0, 3.6), 1.1)
			crystal.mesh = prism
			crystal.material_override = CollisionManager.make_material(color, 0.9)
			crystal.position.y = prism.size.y / 2.0
			crystal.rotation.y = rng.randf_range(0.0, TAU)
			root.add_child(crystal)
		"coral":
			var stalk := MeshInstance3D.new()
			var stalk_mesh := CylinderMesh.new()
			stalk_mesh.top_radius = 0.22
			stalk_mesh.bottom_radius = 0.3
			stalk_mesh.height = 1.8
			stalk.mesh = stalk_mesh
			stalk.material_override = CollisionManager.make_material(color)
			stalk.position.y = 0.9
			root.add_child(stalk)
			var bulb := MeshInstance3D.new()
			var bulb_mesh := SphereMesh.new()
			bulb_mesh.radius = 0.65
			bulb_mesh.height = 1.3
			bulb.mesh = bulb_mesh
			bulb.material_override = CollisionManager.make_material(accent, 0.4)
			bulb.position.y = 2.1
			root.add_child(bulb)
		"mushrooms":
			var stem := MeshInstance3D.new()
			var stem_mesh := CylinderMesh.new()
			stem_mesh.top_radius = 0.3
			stem_mesh.bottom_radius = 0.45
			stem_mesh.height = 1.6
			stem.mesh = stem_mesh
			stem.material_override = CollisionManager.make_material(accent)
			stem.position.y = 0.8
			root.add_child(stem)
			var cap := MeshInstance3D.new()
			var cap_mesh := SphereMesh.new()
			cap_mesh.radius = 1.15
			cap_mesh.height = 1.4
			cap.mesh = cap_mesh
			cap.material_override = CollisionManager.make_material(color, 0.3)
			cap.position.y = 1.9
			root.add_child(cap)
		"pillars":
			var h := rng.randf_range(4.0, 8.0)
			var pillar := CollisionManager.box_mesh(Vector3(0.7, h, 0.7), color, 0.9)
			pillar.position.y = h / 2.0
			root.add_child(pillar)
			var tip := CollisionManager.box_mesh(Vector3(1.1, 0.4, 1.1), accent, 1.2)
			tip.position.y = h + 0.2
			root.add_child(tip)
		_:
			var rock := CollisionManager.box_mesh(Vector3(1.2, 0.9, 1.2), accent)
			rock.position.y = 0.45
			root.add_child(rock)
	return root

## Phase 03 generated-level structures: platforms, moving platforms,
## speed gates, bridge rails, tunnel arches. All optional keys —
## handcrafted levels simply don't carry them.
func _build_generated_structures(level: Dictionary, theme: Dictionary, width: float) -> void:
	for p in level.get("platforms", []):
		_root.add_child(CollisionManager.make_static_box(
			Vector3(float(p["w"]), 0.4, float(p["d"])),
			Vector3(float(p["x"]), float(p["y"]) - 0.2, float(p["z"])), theme["accent_color"]))
	for mp in level.get("moving_platforms", []):
		var body := AnimatableBody3D.new()
		body.collision_layer = CollisionManager.LAYER_WORLD
		body.collision_mask = 0
		body.sync_to_physics = true
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(mp["w"]), 0.4, float(mp["d"]))
		shape.shape = box
		body.add_child(shape)
		body.add_child(CollisionManager.box_mesh(box.size, theme["accent_color"], 0.3))
		body.position = Vector3(float(mp["x"]), float(mp["y"]) - 0.2, float(mp["z"]))
		_root.add_child(body)
		_moving_platforms.append({"body": body, "base_x": float(mp["x"]),
			"range": float(mp.get("range", 1.2)), "speed": float(mp.get("speed", 0.8)),
			"phase": float(mp["z"])})
	for g in level.get("gates", []):
		var gx: float = float(g["x"])
		var gz: float = float(g["z"])
		for side in [-1.0, 1.0]:
			var post := CollisionManager.box_mesh(Vector3(0.4, 3.4, 0.4), theme["accent_color"], 0.8)
			post.position = Vector3(gx + side * width / 4.0, 1.7, gz)
			_root.add_child(post)
		var banner := CollisionManager.box_mesh(Vector3(width / 2.0 + 0.4, 0.5, 0.4), theme["accent_color"], 0.8)
		banner.position = Vector3(gx, 3.5, gz)
		_root.add_child(banner)
	for r in level.get("rails", []):
		_root.add_child(CollisionManager.make_static_box(
			Vector3(0.3, 0.6, float(r["len"])),
			Vector3(float(r["x"]), 0.3, float(r["z_center"])), theme["obstacle_color"]))
	for az in level.get("tunnel_arches", []):
		var tz: float = float(az)
		for side in [-1.0, 1.0]:
			var post := CollisionManager.box_mesh(Vector3(0.5, 4.4, 0.5), theme["decor_color"])
			post.position = Vector3(side * (width / 2.0 + 1.0), 2.2, tz)
			_root.add_child(post)
		var roof := CollisionManager.box_mesh(Vector3(width + 2.5, 0.5, 1.2), theme["accent_color"])
		roof.position = Vector3(0, 4.4, tz)
		_root.add_child(roof)

func _make_collectible(pos: Vector3, theme: Dictionary) -> Area3D:
	var pooled := _collectible_pool.acquire("collectible")
	if pooled != null:
		var area := pooled as Area3D
		area.position = pos
		area.set_meta("base_y", pos.y)
		area.monitoring = true
		area.visible = true
		(area.get_child(1) as MeshInstance3D).material_override = \
			CollisionManager.make_material(theme["collectible_color"], 0.7)
		return area
	_collectible_pool.note_created()
	var fresh := CollisionManager.make_collectible(pos, theme["collectible_color"])
	fresh.set_meta("base_y", pos.y)
	fresh.body_entered.connect(_on_collectible_body.bind(fresh))
	return fresh

func _make_obstacle(ob: Dictionary, theme: Dictionary) -> StaticBody3D:
	var color: Color = theme["obstacle_color"]
	var type: String = str(ob["type"])
	var center_y: float = 1.1
	match type:
		"jump":
			center_y = 0.4
		"slide":
			center_y = 1.75
	var pooled := _obstacle_pool.acquire(type)
	if pooled != null:
		var reused := pooled as StaticBody3D
		reused.position = Vector3(float(ob["x"]), center_y, float(ob["z"]))
		(reused.get_child(1) as MeshInstance3D).material_override = \
			CollisionManager.make_material(color)
		return reused
	_obstacle_pool.note_created()
	var body: StaticBody3D
	match type:
		"jump":  # low barrier: jump over it
			body = CollisionManager.make_static_box(
				Vector3(6.0, 0.8, 0.6), Vector3(ob["x"], 0.4, ob["z"]), color, "obstacle")
		"slide":  # high barrier with a gap underneath: slide under it
			body = CollisionManager.make_static_box(
				Vector3(6.0, 1.1, 0.6), Vector3(ob["x"], 1.75, ob["z"]), color, "obstacle")
		_:  # "block": solid cube, steer around it
			body = CollisionManager.make_static_box(
				Vector3(2.2, 2.2, 2.2), Vector3(ob["x"], 1.1, ob["z"]), color, "obstacle")
	body.set_meta("pool_key", type)
	return body

func _on_collectible_body(body: Node3D, area: Area3D) -> void:
	if not _is_active(body):
		return
	if body.global_position.distance_to(area.global_position) > 2.5:
		return
	_collectibles.erase(area)
	area.set_deferred("monitoring", false)
	call_deferred("_release_collectible_deferred", area)
	collectible_picked.emit(area)

func _release_collectible_deferred(area: Area3D) -> void:
	if is_instance_valid(area):
		_collectible_pool.release(area, "collectible")

func _on_pad_body(body: Node3D) -> void:
	if _is_active(body):
		vehicle_pad_entered.emit()

func _on_finish_body(body: Node3D) -> void:
	if _is_active(body):
		finish_reached.emit()
