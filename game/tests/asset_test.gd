extends Node
## Headless test suite for INFINITE WORLD TV Phase 05 (original asset
## & visual production pipeline). Run:
##   godot --headless --path game res://tests/AssetTest.tscn
## Prints PASS/FAIL per check and ASSET_DONE failures=N.

var failures: int = 0

func check(test_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
	else:
		failures += 1
		print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func _ready() -> void:
	print("ASSET_START")
	_test_characters()
	_test_vehicles()
	_test_animation()
	_test_vehicle_animation()
	_test_environment_assets()
	_test_obstacles_collectibles()
	_test_materials_vfx()
	await _test_audio()
	_test_registry()
	print("ASSET_DONE failures=%d" % failures)
	get_tree().quit(mini(failures, 125))

func _test_characters() -> void:
	var names := CharacterFactory.character_names()
	check("four_characters", names.size() == 4, "count=%d" % names.size())
	check("variant_count_3", CharacterFactory.variant_count() == 3)
	var heights := {}
	for character_name in names:
		var spec: Dictionary = CharacterFactory.spec(character_name)
		check("spec_%s" % character_name, not spec.is_empty())
		heights[float(spec["height"])] = true
		for variant in CharacterFactory.variant_count():
			var built := CharacterFactory.build(character_name, variant)
			check("build_%s_v%d" % [character_name, variant], built != null)
			if built == null:
				continue
			var parts_ok: bool = true
			for part in ["Body", "Head", "Accessory", "ArmL", "ArmR", "LegL", "LegR"]:
				if built.get_node_or_null(part) == null:
					parts_ok = false
			check("parts_%s_v%d" % [character_name, variant], parts_ok)
			check("meta_%s" % character_name, str(built.get_meta("character")) == character_name)
			add_child(built)
			built.queue_free()
	check("distinct_silhouettes", heights.size() == 4, "distinct_heights=%d" % heights.size())
	check("unknown_character_null", CharacterFactory.build("Nope") == null)

func _test_vehicles() -> void:
	var names := VehicleFactory.vehicle_names()
	check("five_vehicles", names.size() == 5, "count=%d" % names.size())
	var lengths := {}
	for vehicle_name in names:
		var built := VehicleFactory.build(vehicle_name)
		check("build_%s" % vehicle_name, built != null)
		if built == null:
			continue
		lengths[float(built.get_meta("length"))] = true
		var wheels_ok: bool = true
		for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
			if built.get_node_or_null(wheel_name) == null:
				wheels_ok = false
		check("wheels_%s" % vehicle_name, wheels_ok)
		var spec: Dictionary = VehicleFactory.collision_spec(vehicle_name)
		check("collision_%s" % vehicle_name, spec.has("size") and spec.has("wheel_radius"))
		add_child(built)
		built.queue_free()
	check("distinct_vehicle_lengths", lengths.size() == 5, "distinct=%d" % lengths.size())
	check("unknown_vehicle_null", VehicleFactory.build("Nope") == null)

func _test_animation() -> void:
	check("ten_animation_states", CharacterAnimation.STATES.size() == 10)
	var visual := CharacterFactory.build("Pip", 0)
	add_child(visual)
	var anim := CharacterAnimation.new(visual)
	check("anim_starts_idle", anim.state() == "idle")
	check("anim_idle_to_run", anim.transition_to("run"))
	check("anim_run_to_jump", anim.transition_to("jump"))
	check("anim_jump_to_land", anim.transition_to("land"))
	check("anim_land_to_idle", anim.transition_to("idle"))
	check("anim_rejects_bad_transition", not anim.transition_to("land"))
	check("anim_rejects_unknown", not anim.transition_to("fly"))
	anim.transition_to("run")
	anim.update(0.1, 8.0, false, false)
	check("anim_run_bob", visual.position.y >= 0.0, "bob_y=%.3f" % visual.position.y)
	anim.transition_to("slide")
	anim.update(0.1, 8.0, false, true)
	check("anim_slide_crouch", visual.scale.y < 1.0, "scale_y=%.2f" % visual.scale.y)
	anim.transition_to("run")
	anim.update(0.1, 8.0, true, false)
	check("anim_airborne_to_jump", anim.state() == "jump", "state=%s" % anim.state())
	visual.queue_free()

func _test_vehicle_animation() -> void:
	var root := VehicleFactory.build("SportsCar")
	add_child(root)
	var anim := VehicleAnimation.new(root)
	check("vehicle_anim_four_wheels", anim.wheels().size() == 4)
	anim.update(0.5, 10.0, 0.0, false)
	check("vehicle_wheels_spin", anim.wheel_spin() > 0.0, "spin=%.2f" % anim.wheel_spin())
	var spin_before: float = anim.wheel_spin()
	anim.update(0.5, 0.0, 0.0, false)
	check("vehicle_wheels_stop_at_zero_speed", is_equal_approx(anim.wheel_spin(), spin_before))
	anim.update(0.1, 10.0, 1.0, false)
	var wheel_fl := root.get_node_or_null("WheelFL") as Node3D
	check("vehicle_front_steers", wheel_fl != null and wheel_fl.rotation.y < 0.0, "steer=%.2f" % wheel_fl.rotation.y)
	anim.on_collision(1.0)
	anim.update(0.05, 10.0, 0.0, true)
	check("vehicle_brake_dive", true) # update ran without error under braking
	root.queue_free()

func _test_environment_assets() -> void:
	var worlds := EnvironmentAssetLibrary.world_names()
	check("eight_asset_worlds", worlds.size() == 8)
	var total_props: int = 0
	for world in worlds:
		var kinds := EnvironmentAssetLibrary.prop_kinds(world)
		check("props_%s" % world.replace(" ", "_"), kinds.size() >= 4, "count=%d" % kinds.size())
		total_props += kinds.size()
		for kind in kinds:
			var prop := EnvironmentAssetLibrary.build_prop(world, kind)
			check("build_prop_%s_%s" % [world.replace(" ", "_"), kind], prop != null)
			if prop == null:
				continue
			if EnvironmentAssetLibrary.is_solid(kind):
				check("solid_%s_is_body" % kind, prop is StaticBody3D)
			add_child(prop)
			prop.queue_free()
	check("total_props_min_40", total_props >= 40, "total=%d" % total_props)
	check("unknown_world_no_props", EnvironmentAssetLibrary.prop_kinds("Nope").is_empty())
	check("unknown_prop_null", EnvironmentAssetLibrary.build_prop("Green Valley", "nope") == null)

func _test_obstacles_collectibles() -> void:
	check("eight_obstacles", ObstacleCollectibleLibrary.obstacle_names().size() == 8)
	check("five_collectibles", ObstacleCollectibleLibrary.collectible_names().size() == 5)
	for kind in ObstacleCollectibleLibrary.obstacle_names():
		var meta: Dictionary = ObstacleCollectibleLibrary.obstacle_metadata(kind)
		check("obstacle_meta_%s" % kind, meta.has("size") and meta.has("hazard") and meta.has("moves"))
		var built := ObstacleCollectibleLibrary.build_obstacle(kind)
		check("build_obstacle_%s" % kind, built != null and built.is_in_group("obstacle"))
		if built != null:
			add_child(built)
			built.queue_free()
	for kind in ObstacleCollectibleLibrary.collectible_names():
		var meta: Dictionary = ObstacleCollectibleLibrary.collectible_metadata(kind)
		check("collectible_meta_%s" % kind, meta.has("score") and meta.has("effect"))
		var built := ObstacleCollectibleLibrary.build_collectible(kind)
		check("build_collectible_%s" % kind, built != null and built.is_in_group("collectible"))
		if built != null:
			add_child(built)
			built.queue_free()
	var total_score: int = 0
	for kind in ObstacleCollectibleLibrary.collectible_names():
		total_score += int((ObstacleCollectibleLibrary.collectible_metadata(kind))["score"])
	check("collectible_scores_positive", total_score > 0, "total_score=%d" % total_score)

func _test_materials_vfx() -> void:
	for world in EnvironmentAssetLibrary.world_names():
		var palette: Dictionary = MaterialLibrary.palette(world)
		check("palette_%s" % world.replace(" ", "_"), palette.size() >= 8, "entries=%d" % palette.size())
		var lighting: Dictionary = MaterialLibrary.lighting_preset(world)
		check("lighting_%s" % world.replace(" ", "_"), lighting.has("sun_energy") and lighting.has("fog_density"))
	check("six_vfx", MaterialLibrary.vfx_names().size() == 6)
	for effect_name in MaterialLibrary.vfx_names():
		var vfx := MaterialLibrary.build_vfx(effect_name)
		check("build_vfx_%s" % effect_name, vfx != null and vfx.amount > 0)
		if vfx != null:
			add_child(vfx)
			vfx.queue_free()
	check("unknown_vfx_null", MaterialLibrary.build_vfx("nope") == null)
	check("unknown_palette_empty", MaterialLibrary.palette("Nope").is_empty())

func _test_audio() -> void:
	var audio := AudioLibrary.new()
	add_child(audio)
	var failed: Array[String] = audio.load_all()
	check("audio_all_clips_load", failed.is_empty(), "failed=%s" % str(failed))
	check("audio_clip_count", AudioLibrary.clip_names().size() == 20, "count=%d" % AudioLibrary.clip_names().size())
	var total_len: float = 0.0
	for clip_name in AudioLibrary.clip_names():
		var dur: float = audio.duration(clip_name)
		check("audio_len_%s" % clip_name, dur > 0.0, "dur=%.2f" % dur)
		total_len += dur
	check("audio_total_length", total_len > 10.0, "total=%.1fs" % total_len)
	check("ambience_world_mapping", AudioLibrary.ambience_for_world("Neon City") == "ambience_neon_city")
	check("audio_unknown_null", audio.stream("nope") == null)
	audio.play("coin")
	audio.play_music()
	audio.play_ambience("Green Valley")
	audio.stop_loops()
	audio.queue_free()

func _test_registry() -> void:
	var summary: Dictionary = AssetRegistry.summary()
	check("registry_summary_counts", int(summary["characters"]) == 4 and int(summary["vehicles"]) == 5
		and int(summary["worlds"]) == 8 and int(summary["obstacles"]) == 8
		and int(summary["collectibles"]) == 5, str(summary))
	var audio := AudioLibrary.new()
	add_child(audio)
	var errors: Array[String] = AssetRegistry.validate(audio)
	check("registry_validates_clean", errors.is_empty(), "errors=%s" % str(errors))
	audio.queue_free()
