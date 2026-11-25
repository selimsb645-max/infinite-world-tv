extends Node
## Headless integration suite for INFINITE WORLD TV Phase 05.1 —
## the Phase 05 factories wired into the LIVE game.
## Run: godot --headless --path game res://tests/AssetIntegrationTest.tscn
## Prints PASS/FAIL per check, MEASURED lines for build performance,
## and ASSET_INTEGRATION_LOGIC_DONE failures=N.
##
## Every check drives the real Main scene. The suite also contains
## the regression GUARD: _live_visuals_are_factory() must be true in
## the integrated game and must turn false when the Phase 02
## primitive fallback is forced — proving the guard would catch a
## silent fallback.

var failures: int = 0
var game: Node

func check(test_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
	else:
		failures += 1
		print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func step_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	print("ASSET_INTEGRATION_START")
	_measure_factory_build_times()
	var packed := load("res://scenes/Main.tscn") as PackedScene
	check("main_scene_loads", packed != null)
	if packed == null:
		_finish()
		return
	game = packed.instantiate()
	add_child(game)
	await step_physics(5)
	await _test_character_integration()
	await _test_vehicle_integration()
	await _test_world_integration()
	await _test_gameplay_still_works()
	await _test_generation_still_valid()
	await _test_guard()
	await _test_dashboard_bridge()
	_finish()

# --- Performance measurements (printed, with sanity bounds) --------------

func _measure_factory_build_times() -> void:
	var t0 := Time.get_ticks_usec()
	for i in 20:
		var c := CharacterFactory.build("Pip", 0)
		c.free()
	var char_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	t0 = Time.get_ticks_usec()
	for i in 20:
		var v := VehicleFactory.build("SportsCar")
		v.free()
	var veh_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	t0 = Time.get_ticks_usec()
	for i in 20:
		var p := EnvironmentAssetLibrary.build_prop("Green Valley", "tree")
		p.free()
	var prop_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	print("MEASURED factory_build_ms character=%.2f vehicle=%.2f prop=%.2f" % [char_ms, veh_ms, prop_ms])
	check("factory_builds_fast", char_ms < 50.0 and veh_ms < 50.0 and prop_ms < 50.0,
		"char=%.2f veh=%.2f prop=%.2f ms" % [char_ms, veh_ms, prop_ms])

# --- Character ------------------------------------------------------------

func _test_character_integration() -> void:
	var chara = game.character
	check("live_character_uses_factory", chara.visual_kind() == "factory"
		and chara.factory_visual() != null)
	var fv: Node3D = chara.factory_visual()
	check("live_character_is_selected_default", str(fv.get_meta("character", "")) == "Pip"
		and fv.name == "Character_Pip", "name=%s" % fv.name)
	var parts_ok := true
	for part in ["Body", "Head", "Accessory", "ArmL", "ArmR", "LegL", "LegR"]:
		if fv.get_node_or_null(part) == null:
			parts_ok = false
	check("factory_character_parts_present", parts_ok)
	check("animation_machine_attached", chara.animation_state() != "",
		"state=%s" % chara.animation_state())
	# Variant/character switching on the live controller.
	check("set_character_rejects_unknown", not chara.set_character("Nope")
		and str(chara.factory_visual().get_meta("character", "")) == "Pip")
	check("set_character_switches_live", chara.set_character("Zara", 2)
		and str(chara.factory_visual().get_meta("character", "")) == "Zara"
		and int(chara.factory_visual().get_meta("variant", -1)) == 2
		and chara.factory_visual().name == "Character_Zara")
	chara.set_character("Pip", 0)
	# Animation states from real gameplay.
	game.start_game("character", "Green Valley")
	await step_physics(30)
	check("anim_run_state_in_play", chara.animation_state() in ["run", "sprint"],
		"state=%s" % chara.animation_state())
	for i in 30:
		await get_tree().physics_frame
		if chara.is_on_floor():
			break
	check("anim_jump_and_land", await _exercise_jump(chara))
	var slid: bool = chara.try_slide()
	await step_physics(3)
	check("anim_slide_state", slid and chara.animation_state() == "slide",
		"state=%s" % chara.animation_state())
	for i in 90:
		await get_tree().physics_frame
		if not chara.sliding:
			break
	await step_physics(5)
	check("anim_recovers_to_run_after_slide", chara.animation_state() == "run",
		"state=%s" % chara.animation_state())
	# Recover: run into the level-1 block (same setup as the smoke test).
	chara.reset_to(Vector3(-2.5, 0.15, -61.0))
	var saw_recover := false
	for i in 120:
		await get_tree().physics_frame
		if chara.animation_state() == "recover":
			saw_recover = true
			break
	check("anim_recover_state_on_obstacle_bump", saw_recover,
		"state=%s" % chara.animation_state())
	# Celebrate: GameManager._on_finish_reached calls celebrate()
	# and then synchronously loads the next level (which resets the
	# animation), so the state is checked via the hook itself, and
	# the finish path is verified by its score/level effects.
	game.start_game("character", "Green Valley")
	# Wait until the character is properly running (the state a real
	# finish is reached from; "land" right after spawn cannot
	# transition to celebrate by the machine's own rules).
	for i in 60:
		await get_tree().physics_frame
		if chara.animation_state() == "run":
			break
	chara.celebrate()
	check("anim_celebrate_on_finish", chara.animation_state() == "celebrate",
		"state=%s" % chara.animation_state())
	var score_before: int = game.score
	game._on_finish_reached()
	check("finish_path_scores_and_advances", game.score == score_before + 100,
		"score %d -> %d" % [score_before, game.score])
	game.load_level_public(0)  # undo the finish's level advance (0-based)

func _exercise_jump(chara: Node) -> bool:
	var jumped: bool = chara.try_jump()
	if not jumped:
		return false
	var saw_air := false
	var landed := false
	for i in 120:
		await get_tree().physics_frame
		var st: String = chara.animation_state()
		if st in ["jump", "fall"]:
			saw_air = true
		if saw_air and chara.is_on_floor() and st in ["land", "run", "idle"]:
			landed = true
			break
	if not (saw_air and landed):
		return false
	# Let the land state settle back to run (the slide check needs it).
	for i in 40:
		await get_tree().physics_frame
		if chara.animation_state() == "run":
			return true
	return false

# --- Vehicle ----------------------------------------------------------------

func _test_vehicle_integration() -> void:
	var car = game.vehicle
	check("live_vehicle_uses_factory", car.visual_kind() == "factory"
		and car.factory_visual() != null)
	var fv: Node3D = car.factory_visual()
	check("live_vehicle_is_selected_default", str(fv.get_meta("vehicle", "")) == "SportsCar"
		and fv.name == "Vehicle_SportsCar", "name=%s" % fv.name)
	var pivots: Array = car.wheel_pivots()
	var names := {}
	for p in pivots:
		names[p.name] = true
	check("vehicle_four_wheel_pivots", pivots.size() == 4
		and names.has("WheelFL") and names.has("WheelFR")
		and names.has("WheelRL") and names.has("WheelRR"),
		"pivots=%d" % pivots.size())
	var spec := VehicleFactory.collision_spec("SportsCar")
	var shape := (car.get_child(0) as CollisionShape3D).shape as BoxShape3D
	check("vehicle_collision_from_factory_spec", shape != null
		and shape.size.is_equal_approx(spec["size"]),
		"size=%s spec=%s" % [str(shape.size), str(spec["size"])])
	check("set_vehicle_kind_rejects_unknown", not car.set_vehicle_kind("Nope")
		and car.vehicle_kind == "SportsCar")
	check("set_vehicle_kind_switches_live", car.set_vehicle_kind("OffRoad")
		and car.factory_visual().name == "Vehicle_OffRoad")
	car.set_vehicle_kind("SportsCar")
	# Drive for real: wheels must spin from speed, front pivots steer.
	game.load_level_public(1)  # Neon Drive — starts in vehicle mode
	await step_physics(3)
	Input.action_press("accelerate")
	await step_physics(40)
	check("vehicle_wheels_spin_from_speed", car.wheel_spin() > 0.5,
		"spin=%.2f speed=%.2f" % [car.wheel_spin(), car.current_speed()])
	Input.action_press("move_right")
	await step_physics(6)
	var steer_seen := false
	for p in car.wheel_pivots():
		if (p.name == "WheelFL" or p.name == "WheelFR") and absf(p.rotation.y) > 0.03:
			steer_seen = true
	Input.action_release("move_right")
	Input.action_release("accelerate")
	check("vehicle_front_wheels_steer", steer_seen)
	# Mode switching keeps the factory visuals on both controllers.
	game.start_game("character", "Green Valley")
	await step_physics(3)
	game.switch_mode()
	await step_physics(3)
	check("mode_switch_to_vehicle_keeps_factory", game.mode == "vehicle"
		and game.vehicle.active and car.visual_kind() == "factory")
	game.switch_mode()
	await step_physics(3)
	check("mode_switch_back_keeps_factory", game.mode == "character"
		and game.character.active and game.character.visual_kind() == "factory")

# --- World: props, obstacles, collectibles -----------------------------------

func _obstacle_bodies() -> Array:
	var out: Array = []
	for child in game.world_manager._root.get_children():
		if child is StaticBody3D and child.is_in_group("obstacle"):
			out.append(child)
	return out

func _shape_span(body: StaticBody3D) -> Vector2:
	var shape_node := body.get_child(0) as CollisionShape3D
	var box := shape_node.shape as BoxShape3D
	var center: float = body.global_position.y + shape_node.position.y
	return Vector2(center - box.size.y * 0.5, center + box.size.y * 0.5)

func _test_world_integration() -> void:
	game.load_level_public(0)
	# All eight worlds: decor comes from that world's Phase 05 prop
	# library, sits off-route, and uses only non-solid decor kinds.
	var level_width: float = 14.0  # handcrafted level 1 width
	for world in EnvironmentAssetLibrary.world_names():
		game.start_game("character", world)
		await step_physics(2)
		var prefix := "Prop_%s_" % world.replace(" ", "")
		var props: Array = []
		for child in game.world_manager._root.get_children():
			if child.name.begins_with(prefix):
				props.append(child)
		var kinds_ok := props.size() > 0
		var route_clear := true
		for prop in props:
			if EnvironmentAssetLibrary.is_solid(str(prop.get_meta("prop", ""))):
				kinds_ok = false
			if absf(prop.global_position.x) < level_width * 0.5 + 2.0:
				route_clear = false
		check("world_props_%s" % world.replace(" ", "_"), kinds_ok and route_clear,
			"props=%d kinds_ok=%s route_clear=%s" % [props.size(), kinds_ok, route_clear])
	# Obstacles in handcrafted level 1: library kinds, real collision,
	# affordances preserved (jump grounded & ~1 m, slide gap >= 1.1 m).
	game.start_game("character", "Green Valley")
	await step_physics(2)
	var bodies := _obstacle_bodies()
	var kinds := {}
	var jump_ok := false
	var slide_ok := false
	var block_ok := false
	for body in bodies:
		var kind := str(body.get_meta("obstacle_kind", ""))
		kinds[kind] = true
		var span := _shape_span(body)
		match str(body.get_meta("pool_key", "")):
			"jump":
				jump_ok = jump_ok or (span.x > -0.05 and span.x < 0.05
					and absf(span.y - 1.0) < 0.05)
			"slide":
				slide_ok = slide_ok or span.x >= 1.1
			"block":
				block_ok = block_ok or (span.x > -0.05 and span.x < 0.05)
	check("obstacles_are_phase05_library_kinds", bodies.size() >= 5
		and kinds.has("jump_gate") and kinds.has("sliding_barrier")
		and kinds.has("road_barrier"),
		"bodies=%d kinds=%s" % [bodies.size(), str(kinds.keys())])
	check("jump_obstacle_grounded_and_jumpable", jump_ok)
	check("slide_obstacle_keeps_gap", slide_ok)
	check("block_obstacle_grounded", block_ok)
	# Collectibles: library coins with live detection settings.
	var coins: Array = []
	for child in game.world_manager._root.get_children():
		if child is Area3D and child.is_in_group("collectible"):
			coins.append(child)
	var coins_ok := coins.size() > 0
	for area in coins:
		if str(area.get_meta("collectible", "")) != "coin":
			coins_ok = false
		if area.collision_mask != CollisionManager.LAYER_PLAYER:
			coins_ok = false
	check("collectibles_are_phase05_coins", coins_ok, "coins=%d" % coins.size())
	# Pickup through the real path still scores.
	var before: int = game.score
	game.character.reset_to(Vector3(0, 0.15, -11.0))  # collectible at z=-15
	await step_physics(25)
	check("collectible_pickup_scores_live", game.score > before,
		"score %d -> %d" % [before, game.score])
	# Pooling stays bounded and reuses the library nodes.
	game.start_game("character", "Neon City")
	await step_physics(2)
	game.start_game("character", "Green Valley")
	await step_physics(2)
	var stats: Dictionary = game.world_manager.pool_stats()
	check("pooling_bounded_and_reused",
		int(stats["obstacles_reused"]) > 0 and int(stats["obstacle_pool_size"]) <= 48,
		"reused=%d pool=%d" % [stats["obstacles_reused"], stats["obstacle_pool_size"]])
	# Node count + level build time for the live scene (measured).
	var t0 := Time.get_ticks_usec()
	game.start_game("character", "Space World")
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	await step_physics(2)
	var nodes := _count_nodes(game)
	print("MEASURED live_scene nodes=%d level_build_ms=%.1f static_mem_mb=%.1f" % [
		nodes, build_ms, float(OS.get_static_memory_usage()) / 1048576.0])
	check("live_scene_node_count_sane", nodes > 100 and nodes < 5000, "nodes=%d" % nodes)

func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total

# --- Gameplay / AI / capture still work ---------------------------------------

func _test_gameplay_still_works() -> void:
	# Autonomous play on generated levels with the integrated visuals.
	game.start_autonomous(4242)
	await step_physics(5)
	var ac = game.autonomous_controller
	var start_pos: Vector3 = game.active_controller().global_position
	await step_physics(600)
	var stats: Dictionary = ac.stats()
	var travelled: float = start_pos.distance_to(game.active_controller().global_position)
	check("ai_autopilot_plays_with_factory_visuals",
		int(stats.get("decisions", 0)) > 0 and travelled > 15.0,
		"decisions=%d travelled=%.1f" % [int(stats.get("decisions", 0)), travelled])
	check("ai_run_keeps_factory_visuals", game.character.visual_kind() == "factory"
		and game.vehicle.visual_kind() == "factory")

func _test_generation_still_valid() -> void:
	var gen := LevelGenerator.new()
	var val := LevelValidator.new()
	var dm := DifficultyManager.new()
	var all_valid := true
	for i in 25:
		var level_number: int = 1 + (i % 5)
		var r: Dictionary = gen.generate(level_number, 9000 + i)
		if not bool(r.get("ok", false)):
			all_valid = false
			break
		if not bool(val.validate(r["level"], dm.profile_for(level_number))["valid"]):
			all_valid = false
			break
	check("generation_still_valid_25_levels", all_valid)

# --- The guard ------------------------------------------------------------------

## The Phase 05.1 regression guard: true only while the LIVE game is
## actually using the Phase 05 factory/library visuals everywhere
## they are expected. Any silent fallback to Phase 02 primitives
## (controller toggle, env override, lost wiring) turns this false.
func _live_visuals_are_factory(g: Node) -> bool:
	if g.character.visual_kind() != "factory":
		return false
	if g.vehicle.visual_kind() != "factory":
		return false
	var saw_prop := false
	var saw_obstacle := false
	var saw_coin := false
	for child in g.world_manager._root.get_children():
		if child.name.begins_with("Prop_"):
			saw_prop = true
		if child is StaticBody3D and child.is_in_group("obstacle"):
			if str(child.get_meta("obstacle_kind", "")) == "":
				return false
			saw_obstacle = true
		if child is Area3D and child.is_in_group("collectible"):
			if str(child.get_meta("collectible", "")) != "coin":
				return false
			saw_coin = true
	return saw_prop and saw_obstacle and saw_coin

func _test_guard() -> void:
	game.start_game("character", "Green Valley")
	await step_physics(3)
	check("guard_factory_integration_present", _live_visuals_are_factory(game))
	# Force the Phase 02 fallback: the guard MUST catch it.
	game.set_factory_visuals_enabled(false)
	await step_physics(2)
	check("guard_catches_primitive_fallback", not _live_visuals_are_factory(game)
		and game.character.visual_kind() == "primitive"
		and game.vehicle.visual_kind() == "primitive")
	# Restore: integration is back and the guard is green again.
	game.set_factory_visuals_enabled(true)
	await step_physics(2)
	check("guard_green_after_restore", _live_visuals_are_factory(game))

# --- Dashboard bridge accuracy ----------------------------------------------------

func _test_dashboard_bridge() -> void:
	var dir := ProjectSettings.globalize_path("res://../recordings/qa_dash_tmp")
	OS.set_environment("IWT_DASHBOARD_DIR", dir)
	var service := load("res://dashboard/GameService.tscn") as PackedScene
	check("game_service_scene_loads", service != null)
	if service == null:
		return
	var svc = service.instantiate()
	add_child(svc)
	await get_tree().create_timer(0.6).timeout
	# Drive the real game through the bridge's own command channel.
	var cmd := {"id": "qa1", "action": "start_game", "params": {}}
	var f := FileAccess.open(dir.path_join("game_cmd.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(cmd))
	f.close()
	await get_tree().create_timer(1.6).timeout
	var status_path := dir.path_join("game_status.json")
	var ok := FileAccess.file_exists(status_path)
	var state := ""
	var world := ""
	if ok:
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(status_path))
		if parsed is Dictionary:
			state = str(parsed.get("state", ""))
			world = str(parsed.get("world", ""))
	check("dashboard_bridge_reports_real_state", ok and state == "PLAYING",
		"state=%s world=%s" % [state, world])
	svc.queue_free()
	OS.set_environment("IWT_DASHBOARD_DIR", "")

func _finish() -> void:
	print("ASSET_INTEGRATION_LOGIC_DONE failures=%d" % failures)
	get_tree().quit(mini(failures, 125))
