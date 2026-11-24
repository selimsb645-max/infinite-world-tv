extends Node
## Headless smoke test for INFINITE WORLD TV Phase 02.
## Run: godot --headless --path game res://tests/SmokeTest.tscn
## Prints PASS/FAIL lines and SMOKE_DONE failures=N, exits with that code.
## Every check drives the real game scene and real physics.

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
	print("SMOKE_START")
	var packed := load("res://scenes/Main.tscn") as PackedScene
	check("main_scene_loads", packed != null)
	if packed == null:
		_finish()
		return
	game = packed.instantiate()
	add_child(game)
	await step_physics(5)
	check("game_ready", game.character != null and game.vehicle != null)

	# --- Character movement / strafe / jump / slide -------------------
	game.start_game("character", "Green Valley")
	await step_physics(3)
	var chara = game.character
	var start_z: float = chara.global_position.z
	await step_physics(20)
	check("character_runs_forward", chara.global_position.z < start_z - 1.0,
		"z %.2f -> %.2f" % [start_z, chara.global_position.z])
	var start_x: float = chara.global_position.x
	Input.action_press("move_right")
	await step_physics(12)
	Input.action_release("move_right")
	check("character_strafes_right", chara.global_position.x > start_x + 0.3,
		"x %.2f -> %.2f" % [start_x, chara.global_position.x])
	# wait until grounded, then jump
	for i in 30:
		await get_tree().physics_frame
		if chara.is_on_floor():
			break
	var ground_y: float = chara.global_position.y
	var jumped: bool = chara.try_jump()
	await step_physics(6)
	check("character_jumps", jumped and chara.global_position.y > ground_y + 0.25,
		"y %.2f -> %.2f" % [ground_y, chara.global_position.y])
	for i in 60:
		await get_tree().physics_frame
		if chara.is_on_floor():
			break
	var slid: bool = chara.try_slide()
	await step_physics(2)
	check("character_slides", slid and chara.sliding)
	for i in 60:
		await get_tree().physics_frame
		if not chara.sliding:
			break
	check("character_slide_ends", not chara.sliding)

	# --- Collision: a "block" obstacle must stop the runner -----------
	# Level 1 has a block at (-2.5, -65). Teleport just before it, in its lane.
	chara.reset_to(Vector3(-2.5, 0.15, -61.0))
	await step_physics(45)
	check("character_blocked_by_obstacle", chara.global_position.z > -67.5,
		"stopped at z=%.2f (block front at -63.9)" % chara.global_position.z)

	# --- Mode switch ---------------------------------------------------
	game.switch_mode()
	await step_physics(3)
	check("switch_to_vehicle", game.mode == "vehicle" and game.vehicle.active
		and not game.character.active and game.camera_rig.target == game.vehicle)
	game.switch_mode()
	await step_physics(3)
	check("switch_back_to_character", game.mode == "character" and game.character.active
		and game.camera_rig.target == game.character)

	# --- Vehicle driving ----------------------------------------------
	game.load_level_public(1)  # Level 2 — Neon Drive, starts in vehicle mode
	await step_physics(3)
	var car = game.vehicle
	check("vehicle_level_starts_in_vehicle_mode", game.mode == "vehicle" and car.active)
	Input.action_press("accelerate")
	await step_physics(40)
	Input.action_release("accelerate")
	check("vehicle_accelerates", car.current_speed() > 3.0, "speed=%.2f" % car.current_speed())
	var car_z: float = car.global_position.z
	await step_physics(10)
	check("vehicle_moves", car.global_position.z < car_z - 0.5,
		"z %.2f -> %.2f" % [car_z, car.global_position.z])
	Input.action_press("brake")
	await step_physics(20)
	Input.action_release("brake")
	check("vehicle_brakes", car.current_speed() < 1.5, "speed=%.2f" % car.current_speed())

	# --- Camera follows -------------------------------------------------
	game.start_game("character", "Green Valley")
	await step_physics(30)
	var rig = game.camera_rig
	var dist: float = rig.global_position.distance_to(game.character.global_position)
	check("camera_follows_character", dist > 4.0 and dist < 14.0, "dist=%.2f" % dist)
	check("camera_behind_character", rig.global_position.z > game.character.global_position.z)

	# --- Themes ---------------------------------------------------------
	var env = game.environment_manager
	var skies := {}
	var all_ok := true
	for theme_name in EnvironmentManager.THEME_NAMES:
		if not env.apply_theme(theme_name):
			all_ok = false
		skies[env.sky_color_of(theme_name)] = true
	check("five_themes_apply", all_ok and env.current_theme == "Space World")
	check("five_themes_distinct_skies", skies.size() == 5, "distinct=%d" % skies.size())
	env.apply_theme("Green Valley")

	# --- Levels ---------------------------------------------------------
	check("level_count", game.level_manager.level_count() >= 2,
		"count=%d" % game.level_manager.level_count())
	game.load_level_public(2)
	await step_physics(3)
	check("level_3_loads", game.level_manager.current_index == 2)
	game.load_level_public(0)
	await step_physics(3)
	check("level_1_reloads", game.level_manager.current_index == 0)

	# --- Collectible scoring ---------------------------------------------
	game.start_game("character", "Green Valley")
	await step_physics(3)
	var before: int = game.score
	game.character.reset_to(Vector3(0, 0.15, -11.0))  # collectible at z=-15
	await step_physics(25)
	check("collectible_scores", game.score > before,
		"score %d -> %d" % [before, game.score])

	# --- Pause / resume ---------------------------------------------------
	game.toggle_pause()
	check("pause_sets_tree_paused", get_tree().paused and game.state == 2)  # State.PAUSED
	game.resume_game()
	check("resume_unpauses", not get_tree().paused and game.state == 1)  # State.PLAYING

	# --- Restart ------------------------------------------------------------
	game.add_score(50)
	game.restart_level()
	await step_physics(3)
	check("restart_resets_score", game.score == 0, "score=%d" % game.score)
	check("restart_returns_to_spawn",
		game.character.global_position.distance_to(Vector3(0, 0.15, 4.0)) < 2.5,
		"pos=%s" % str(game.character.global_position))
	_finish()

func _finish() -> void:
	print("SMOKE_DONE failures=%d" % failures)
	get_tree().quit(mini(failures, 125))
