extends Node
## Visual QA for INFINITE WORLD TV Phase 05.1 — runs the LIVE game
## under a real (Xvfb) display and checks actual rendered pixels:
## the factory character's signature colour in frame, the factory
## vehicle's signature colour in frame, every world's sky colour
## and prop presence, a character->vehicle transition frame, and
## the Phase 06 broadcast overlay changing real pixels.
## Run: xvfb-run godot --path game res://tests/VisualQaTest.tscn
## (NOT --headless: real pixels are the point.)
## Prints PASS/FAIL per check, MEASURED fps lines, VISUAL_QA_DONE.
##
## With IWT_FACTORY_VISUALS=0 the same scene runs in Phase 02
## primitive mode: signature checks are skipped (the primitives do
## not carry those colours) and only frame sanity + FPS are
## reported, for the before/after performance comparison.
##
## Screenshots land in <project>/screenshots/qa/ (gitignored).

var failures: int = 0
var game: Node
var factory_mode: bool = true
var shot_dir: String

func check(test_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
	else:
		failures += 1
		print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func _ready() -> void:
	print("VISUAL_QA_START")
	factory_mode = OS.get_environment("IWT_FACTORY_VISUALS").strip_edges() != "0"
	shot_dir = ProjectSettings.globalize_path("res://../screenshots/qa")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var packed := load("res://scenes/Main.tscn") as PackedScene
	game = packed.instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	await _shot_character()
	await _shot_transition_and_vehicle()
	await _shot_worlds()
	await _shot_overlay()
	await _measure_fps()
	print("VISUAL_QA_DONE failures=%d mode=%s" % [
		failures, "factory" if factory_mode else "primitive"])
	get_tree().quit(mini(failures, 125))

# --- Frame helpers ---------------------------------------------------------

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _save(img: Image, file_name: String) -> void:
	img.save_png(shot_dir.path_join(file_name))

func _image_hash(img: Image) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(img.get_data())
	return ctx.finish().hex_encode()

func _frame_varied(img: Image) -> bool:
	# A rendered 3D frame has plenty of distinct colours; a blank or
	# stuck frame does not. Sample a coarse grid.
	var seen := {}
	var w := img.get_width()
	var h := img.get_height()
	for x in range(0, w, 16):
		for y in range(0, h, 16):
			var c := img.get_pixel(x, y)
			seen[Vector3i(int(c.r * 24), int(c.g * 24), int(c.b * 24))] = true
	return seen.size() > 24

func _window_pixels(img: Image, center: Vector2, radius: int) -> Array:
	var out: Array = []
	var x0: int = maxi(0, int(center.x) - radius)
	var x1: int = mini(img.get_width() - 1, int(center.x) + radius)
	var y0: int = maxi(0, int(center.y) - radius)
	var y1: int = mini(img.get_height() - 1, int(center.y) + radius)
	for x in range(x0, x1, 2):
		for y in range(y0, y1, 2):
			out.append(img.get_pixel(x, y))
	return out

func _count_dominant(pixels: Array, channel: String) -> int:
	var n := 0
	for c in pixels:
		match channel:
			"purple":  # Nova body (0.65, 0.35, 0.85)
				if c.b > c.r + 0.06 and c.b > c.g + 0.10 and c.b > 0.35:
					n += 1
			"red":  # SportsCar body (0.9, 0.15, 0.2)
				if c.r > c.g + 0.14 and c.r > c.b + 0.10 and c.r > 0.35:
					n += 1
	return n

func _screen_pos(world_pos: Vector3) -> Vector2:
	return get_viewport().get_camera_3d().unproject_position(world_pos)

# --- Shots -------------------------------------------------------------------

func _shot_character() -> void:
	if factory_mode:
		game.character.set_character("Nova", 0)
	game.start_game("character", "Green Valley")
	await get_tree().create_timer(1.2).timeout
	var img := await _grab()
	_save(img, "qa_character.png")
	check("qa_character_frame_rendered", _frame_varied(img),
		"size=%s" % str(img.get_size()))
	if factory_mode:
		var centre := _screen_pos(game.character.global_position + Vector3(0, 0.85, 0))
		var hits := _count_dominant(_window_pixels(img, centre, 46), "purple")
		check("qa_character_factory_colours_in_frame", hits > 25,
			"nova_purple_pixels=%d" % hits)

func _shot_transition_and_vehicle() -> void:
	# The car comes to the runner: one frame right after the switch
	# shows the transition result (vehicle live at the character).
	game.switch_mode()
	await get_tree().create_timer(0.8).timeout
	var img := await _grab()
	_save(img, "qa_transition.png")
	check("qa_transition_switched_mode", game.mode == "vehicle"
		and game.vehicle.active)
	if factory_mode:
		var centre := _screen_pos(game.vehicle.global_position + Vector3(0, 0.5, 0))
		var hits := _count_dominant(_window_pixels(img, centre, 52), "red")
		check("qa_vehicle_factory_colours_in_frame", hits > 25,
			"sportscar_red_pixels=%d" % hits)
	# Let it drive, then a clean vehicle-in-play frame.
	Input.action_press("accelerate")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("accelerate")
	img = await _grab()
	_save(img, "qa_vehicle.png")
	check("qa_vehicle_frame_rendered", _frame_varied(img))

func _shot_worlds() -> void:
	var env := EnvironmentManager.new()
	for world in EnvironmentAssetLibrary.world_names():
		game.load_level_public(0)
		game.start_game("character", world)
		await get_tree().create_timer(0.9).timeout
		var img := await _grab()
		_save(img, "qa_world_%s.png" % world.replace(" ", "_"))
		# Sky: average the top strip and compare with the theme sky.
		var sum := Vector3.ZERO
		var count := 0
		for x in range(8, img.get_width() - 8, 24):
			for y in range(4, 44, 8):
				var c := img.get_pixel(x, y)
				sum += Vector3(c.r, c.g, c.b)
				count += 1
		var avg := sum / float(count)
		var sky: Color = env.sky_color_of(world)
		var diff: float = maxf(absf(avg.x - sky.r),
			maxf(absf(avg.y - sky.g), absf(avg.z - sky.b)))
		check("qa_world_sky_%s" % world.replace(" ", "_"), diff < 0.30,
			"avg=(%.2f,%.2f,%.2f) sky=(%.2f,%.2f,%.2f) diff=%.2f" % [
				avg.x, avg.y, avg.z, sky.r, sky.g, sky.b, diff])
		if factory_mode:
			var prefix := "Prop_%s_" % world.replace(" ", "")
			var props := 0
			for child in game.world_manager._root.get_children():
				if child.name.begins_with(prefix):
					props += 1
			check("qa_world_props_%s" % world.replace(" ", "_"), props > 0,
				"props=%d" % props)

func _shot_overlay() -> void:
	var cfg := EncodingConfig.preset_720p(15)
	cfg.output_dir = ProjectSettings.globalize_path("res://../recordings/qa_overlay_tmp")
	var renderer = game.setup_broadcast(cfg)
	check("qa_broadcast_renderer_created", renderer != null)
	if renderer == null:
		return
	await get_tree().create_timer(0.8).timeout
	var with_overlay := await _grab()
	_save(with_overlay, "qa_overlay.png")
	renderer.overlay.visible = false
	await RenderingServer.frame_post_draw
	var without_overlay := await _grab()
	renderer.overlay.visible = true
	check("qa_overlay_changes_pixels",
		_image_hash(with_overlay) != _image_hash(without_overlay))

func _measure_fps() -> void:
	game.start_autonomous(99)
	var frames := 0
	var end_msec := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < end_msec:
		await get_tree().process_frame
		frames += 1
	print("MEASURED qa_fps=%.2f mode=%s" % [
		frames / 6.0, "factory" if factory_mode else "primitive"])
	check("qa_fps_measured_positive", frames > 0, "frames=%d" % frames)
