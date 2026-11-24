extends Node
## Headless test suite for INFINITE WORLD TV Phase 03 (procedural
## generation engine). Run:
##   godot --headless --path game res://tests/GenerationTest.tscn
## Prints PASS/FAIL per check, a GEN_STATS summary with real numbers
## from the 1,000-level run, and GEN_DONE failures=N.

var failures: int = 0

func check(test_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
	else:
		failures += 1
		print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func step_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _has_error(errors: Array, needle: String) -> bool:
	for e in errors:
		if str(e).contains(needle):
			return true
	return false

func _ready() -> void:
	print("GEN_START")
	_test_worlds()
	_test_reproducibility()
	_test_difficulty()
	_test_validator_rejections()
	_test_repetition()
	_test_fallback_and_recovery()
	_test_history_and_queue()
	_test_thousand_levels()
	await _test_integration()
	print("GEN_DONE failures=%d" % failures)
	get_tree().quit(mini(failures, 125))

# --- Worlds ---------------------------------------------------------------

func _test_worlds() -> void:
	var names: Array[String] = WorldGenerator.world_names()
	check("eight_worlds_registered", names.size() == 8, "count=%d" % names.size())
	var env := EnvironmentManager.new()
	var skies := {}
	var all_themed: bool = true
	for n in names:
		if not env.has_theme(n):
			all_themed = false
		else:
			skies[env.sky_color_of(n)] = true
	check("eight_world_themes_exist", all_themed)
	check("eight_worlds_distinct_skies", skies.size() == 8, "distinct=%d" % skies.size())
	for required in ["Ocean World", "Fantasy Islands", "Futuristic Highway"]:
		check("new_world_present_%s" % required.replace(" ", "_"), names.has(required))

# --- Reproducibility --------------------------------------------------------

func _test_reproducibility() -> void:
	var g1 := LevelGenerator.new()
	var g2 := LevelGenerator.new()
	var r1: Dictionary = g1.generate(1, 4242)
	var r2: Dictionary = g2.generate(1, 4242)
	check("seed_reproducibility_fingerprint",
		str(r1["meta"]["fingerprint"]) == str(r2["meta"]["fingerprint"]))
	var o1: Array = r1["level"]["obstacles"]
	var o2: Array = r2["level"]["obstacles"]
	var same_layout: bool = o1.size() == o2.size()
	if same_layout and o1.size() > 0:
		same_layout = str(o1[0]) == str(o2[0]) and str(o1[o1.size() - 1]) == str(o2[o2.size() - 1])
	check("seed_reproducibility_layout", same_layout, "obstacles=%d" % o1.size())
	var g3 := LevelGenerator.new()
	var prints := {}
	for i in range(1, 21):
		var r: Dictionary = g3.generate(i, 1000 + i)
		prints[str(r["meta"]["fingerprint"])] = true
	check("distinct_seeds_distinct_levels", prints.size() >= 19,
		"distinct=%d/20" % prints.size())

# --- Difficulty ---------------------------------------------------------------

func _test_difficulty() -> void:
	var dm := DifficultyManager.new()
	var p1: Dictionary = dm.profile_for(1)
	var p20: Dictionary = dm.profile_for(20)
	var p41: Dictionary = dm.profile_for(41)
	var p500: Dictionary = dm.profile_for(500)
	check("difficulty_rises", float(p1["index"]) < float(p20["index"])
		and float(p20["index"]) < float(p41["index"]),
		"%.2f<%.2f<%.2f" % [p1["index"], p20["index"], p41["index"]])
	check("difficulty_capped", float(p500["index"]) == float(p41["index"]),
		"cap=%.2f" % float(p41["index"]))
	check("difficulty_spacing_shrinks", float(p1["min_spacing"]) > float(p41["min_spacing"]))
	check("difficulty_obstacles_grow", int(p1["obstacles_per_segment"]) < int(p41["obstacles_per_segment"]))
	var eased: Dictionary = dm.profile_for(41, {"deaths": 5})
	check("difficulty_performance_eases", float(eased["index"]) < float(p41["index"]))

# --- Validator ------------------------------------------------------------------

func _test_validator_rejections() -> void:
	var gen := LevelGenerator.new()
	var r: Dictionary = gen.generate(1, 31337)
	var base: Dictionary = r["level"]
	var dm := DifficultyManager.new()
	var diff: Dictionary = dm.profile_for(1)
	var val := LevelValidator.new()
	check("generated_level_validates", bool(val.validate(base, diff)["valid"]))

	var v1: Dictionary = base.duplicate(true)
	(v1["obstacles"] as Array).append({"type": "jump", "x": 0.0, "z": -3.0})
	var c1: Dictionary = val.validate(v1, diff)
	check("validator_rejects_spawn_obstacle", not bool(c1["valid"])
		and _has_error(c1["errors"], "spawn"), str(c1["errors"]))

	var v2: Dictionary = base.duplicate(true)
	(v2["obstacles"] as Array).append({"type": "block", "x": 0.0, "z": -30.0})
	(v2["obstacles"] as Array).append({"type": "block", "x": 0.5, "z": -30.5})
	var c2: Dictionary = val.validate(v2, diff)
	check("validator_rejects_tight_spacing", not bool(c2["valid"])
		and _has_error(c2["errors"], "too_close"), str(c2["errors"]))

	var v3: Dictionary = base.duplicate(true)
	(v3["gaps"] as Array).append({"z_center": -40.0, "len": 6.5})
	(v3["platforms"] as Array).append({"x": 0.0, "y": 0.5, "z": -40.0, "w": 3.0, "d": 9.0})
	var c3: Dictionary = val.validate(v3, diff)
	check("validator_rejects_long_gap", not bool(c3["valid"])
		and _has_error(c3["errors"], "gap_too_long"), str(c3["errors"]))

	var v4: Dictionary = base.duplicate(true)
	(v4["platforms"] as Array).append({"x": 0.0, "y": 2.2, "z": -50.0, "w": 3.0, "d": 3.0})
	var c4: Dictionary = val.validate(v4, diff)
	check("validator_rejects_high_platform", not bool(c4["valid"])
		and _has_error(c4["errors"], "platform_too_high"), str(c4["errors"]))

	var minimal: Dictionary = {
		"length": 100.0, "width": 5.0, "segments": [{"mode": "vehicle", "lane_offset": 0.0}],
		"obstacles": [{"type": "block", "x": 0.0, "z": -30.0}],
		"collectibles": [], "gaps": [], "platforms": [], "moving_platforms": [],
		"ground_strips": [], "vehicle_pad_z": -50.0,
	}
	var c5: Dictionary = val.validate(minimal, diff)
	check("validator_rejects_blocked_corridor", not bool(c5["valid"])
		and _has_error(c5["errors"], "vehicle_corridor_blocked"), str(c5["errors"]))

	var v6: Dictionary = base.duplicate(true)
	var ob0: Dictionary = (v6["obstacles"] as Array)[0]
	(v6["collectibles"] as Array).append(Vector3(float(ob0["x"]), 1.0, float(ob0["z"])))
	var c6: Dictionary = val.validate(v6, diff)
	check("validator_rejects_collectible_in_obstacle", not bool(c6["valid"])
		and _has_error(c6["errors"], "collectible_inside_obstacle"), str(c6["errors"]))

# --- Anti-repetition --------------------------------------------------------------

func _test_repetition() -> void:
	var gen := LevelGenerator.new()
	var r1: Dictionary = gen.generate(1, 999)
	var level: Dictionary = r1["level"]
	var dup: Dictionary = gen.anti_repetition.evaluate(level)
	check("duplicate_detected_exact", not bool(dup["accepted"]) and bool(dup["duplicate"]))
	# Same structure, different seed/theme metadata -> still a duplicate,
	# because the fingerprint is structural only.
	var recolor: Dictionary = level.duplicate(true)
	recolor["seed"] = 123456
	recolor["theme_data"] = {}
	var dup2: Dictionary = gen.anti_repetition.evaluate(recolor)
	check("duplicate_detected_despite_reseed", not bool(dup2["accepted"]))
	# Near-copy: change only the last segment's feature token.
	var near: Dictionary = level.duplicate(true)
	var segs: Array = near["segments"]
	var last: Dictionary = (segs[segs.size() - 1] as Dictionary).duplicate()
	last["feature"] = "run" if str(last["feature"]) != "run" else "gates"
	segs[segs.size() - 1] = last
	var sim_eval: Dictionary = gen.anti_repetition.evaluate(near)
	check("similarity_detected_near_copy", not bool(sim_eval["accepted"])
		and not bool(sim_eval["duplicate"])
		and float(sim_eval["max_similarity"]) >= gen.config.similarity_threshold,
		"sim=%.3f" % float(sim_eval["max_similarity"]))
	# Regeneration: asking again for the same level number+seed must
	# produce a DIFFERENT accepted level after bounded retries.
	var r2: Dictionary = gen.generate(1, 999)
	check("regeneration_after_rejection", bool(r2["ok"])
		and int(r2["meta"]["attempts"]) >= 2
		and str(r2["meta"]["fingerprint"]) != str(r1["meta"]["fingerprint"]),
		"attempts=%d" % int(r2["meta"]["attempts"]))

# --- Fallback + recovery -------------------------------------------------------------

func _test_fallback_and_recovery() -> void:
	var cfg := GenerationConfig.new()
	cfg.similarity_threshold = 0.0  # nothing can ever be "fresh enough"
	cfg.max_retries = 3
	var gen := LevelGenerator.new(null, cfg)
	var r: Dictionary = gen.generate(1, 77)
	check("fallback_served_when_retries_exhausted", bool(r["ok"]) and bool(r["meta"]["fallback"]),
		"fallbacks=%d" % gen.fallbacks_used)
	var val := LevelValidator.new()
	var diff: Dictionary = DifficultyManager.new().profile_for(1)
	check("fallback_level_is_valid", bool(val.validate(r["level"], diff)["valid"]))
	# Recovery: restore a sane threshold on the SAME generator/config —
	# the next generation must succeed normally again.
	cfg.similarity_threshold = 0.8
	var r2: Dictionary = gen.generate(2, 78)
	check("generation_recovers_after_fallback", bool(r2["ok"]) and not bool(r2["meta"]["fallback"]))

# --- History bounds + queue --------------------------------------------------------------

func _test_history_and_queue() -> void:
	var cfg := GenerationConfig.new()
	cfg.history_size = 50
	var hist := LevelHistoryManager.new(cfg)
	var fp := LevelFingerprintManager.new()
	for i in 300:
		hist.add({"world": "Green Valley", "seed": i}, "fp%d" % i, {})
	check("history_bounded", hist.size() <= 50, "size=%d" % hist.size())
	check("history_eviction_drops_old_fingerprints", not hist.has_fingerprint("fp0")
		and hist.has_fingerprint("fp299"))

	var gen := LevelGenerator.new()
	for i in range(1, 6):
		gen.enqueue(i, 5000 + i)
	var first: Array = gen.process_queue(2)
	check("queue_budget_respected", first.size() == 2 and gen.pending() == 3,
		"processed=%d pending=%d" % [first.size(), gen.pending()])
	var rest: Array = gen.process_queue(10)
	check("queue_drains", rest.size() == 3 and gen.pending() == 0)

	var tm := LevelTransitionManager.new(LevelGenerator.new())
	tm.start(123)
	var retained_ok: bool = tm.retained_count() <= 2
	for i in 30:
		tm.advance()
		if tm.retained_count() > 2:
			retained_ok = false
	check("transition_keeps_only_two_levels", retained_ok and tm.level_number == 31,
		"level=%d retained=%d" % [tm.level_number, tm.retained_count()])

# --- The 1,000-level run ----------------------------------------------------------------------

func _test_thousand_levels() -> void:
	var gen := LevelGenerator.new()
	var val := LevelValidator.new()
	var dm := DifficultyManager.new()
	var fingerprints := {}
	var worlds := {}
	var mixed_levels: int = 0
	var char_segments: int = 0
	var vehicle_segments: int = 0
	var all_valid: bool = true
	var first_invalid: String = ""
	var t0: int = Time.get_ticks_msec()
	for i in range(1, 1001):
		var r: Dictionary = gen.generate(i, 777000 + i)
		var level: Dictionary = r["level"]
		fingerprints[str(r["meta"]["fingerprint"])] = true
		worlds[str(level["world"])] = true
		var modes := {}
		for seg in level["segments"]:
			modes[str(seg["mode"])] = true
			if str(seg["mode"]) == "character":
				char_segments += 1
			else:
				vehicle_segments += 1
		if modes.has("character") and modes.has("vehicle"):
			mixed_levels += 1
		var recheck: Dictionary = val.validate(level, dm.profile_for(i))
		if not bool(recheck["valid"]):
			all_valid = false
			if first_invalid == "":
				first_invalid = "level %d: %s" % [i, str(recheck["errors"])]
	var elapsed: int = Time.get_ticks_msec() - t0
	print("GEN_STATS levels=1000 distinct_fingerprints=%d worlds=%d mixed=%d char_segments=%d vehicle_segments=%d fallbacks=%d attempts=%d validation_rejections=%d dup_rejected=%d sim_rejected=%d elapsed_ms=%d" % [
		fingerprints.size(), worlds.size(), mixed_levels, char_segments, vehicle_segments,
		gen.fallbacks_used, gen.total_attempts, gen.validation_rejections,
		gen.anti_repetition.rejected_duplicates, gen.anti_repetition.rejected_similar, elapsed])
	check("thousand_levels_all_valid", all_valid, first_invalid)
	check("thousand_levels_no_exact_duplicates", fingerprints.size() == 1000,
		"distinct=%d" % fingerprints.size())
	check("thousand_levels_all_worlds_used", worlds.size() == 8, "worlds=%d" % worlds.size())
	check("thousand_levels_mixed_modes", mixed_levels >= 950, "mixed=%d" % mixed_levels)
	check("thousand_levels_both_modes_present", char_segments > 0 and vehicle_segments > 0,
		"char=%d vehicle=%d" % [char_segments, vehicle_segments])

# --- Integration with the real game scene ---------------------------------------------------------

func _test_integration() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	check("integration_main_scene_loads", packed != null)
	if packed == null:
		return
	var game = packed.instantiate()
	add_child(game)
	await step_physics(5)
	game.start_endless(2024)
	await step_physics(5)
	check("endless_mode_active", game.endless_active
		and game.transition_manager.level_number == 1)
	var root_children: int = 0
	if game.world_manager._root != null:
		root_children = game.world_manager._root.get_child_count()
	check("generated_level_built_in_world", root_children > 10,
		"nodes=%d" % root_children)
	check("generated_level_theme_applied",
		EnvironmentManager.THEMES.has(game.environment_manager.current_theme),
		game.environment_manager.current_theme)
	# Finish -> pregenerated level 2 takes over.
	game._on_finish_reached()
	await step_physics(5)
	check("endless_finish_advances", game.transition_manager.level_number == 2,
		"level=%d" % game.transition_manager.level_number)
	var stats: Dictionary = game.world_manager.pool_stats()
	check("object_pool_reuses_obstacles", int(stats["obstacles_reused"]) > 0,
		"reused=%d created=%d" % [stats["obstacles_reused"], stats["obstacles_created"]])
	# Handcrafted flow still intact after endless.
	game.start_game("character", "Green Valley")
	await step_physics(3)
	check("handcrafted_mode_still_works", not game.endless_active
		and game.level_manager.current_index == 0 and game.character.active)
	game.queue_free()
