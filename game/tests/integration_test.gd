extends Node
## Phase 10 — END-TO-END integration chain, leg 1 (in-engine).
##
## Run under Xvfb (real pixels are required for capture):
##   xvfb-run -a godot --path game res://tests/IntegrationTest.tscn
##
## Exercises the real production chain in ONE continuous session,
## asserting every boundary in sequence:
##   game boot -> Phase 05 asset registry + audio library plan ->
##   autonomous start on a generated level (re-validated live) ->
##   autonomous character AND vehicle gameplay -> Phase 06 capture
##   + render to a real MP4 (ffprobe-validated) -> capture health
##   evaluation -> Phase 07 stream PREPARE with the rendered file
##   as input against a LOCAL ingest target (prepare spawns
##   nothing; nothing leaves this machine) -> public-start
##   safeguard refusal without explicit confirmation.
##
## The runner exports a FAKE stream key + local ingest env:
##   IWT_YOUTUBE_STREAM_KEY, IWT_RTMP_INGEST_URL (127.0.0.1),
##   IWT_STREAM_VISIBILITY, IWT_ADMIN_TOKEN.
## No YouTube endpoint is contacted anywhere in this suite.
##
## Prints PASS/FAIL per check and INTEGRATION_CHAIN_DONE failures=N.

var failures: int = 0

func check(test_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
	else:
		failures += 1
		print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func _recordings_root() -> String:
	return ProjectSettings.globalize_path("res://../recordings")

func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	print("INTEGRATION_CHAIN_START")
	var admin_token := OS.get_environment("IWT_ADMIN_TOKEN").strip_edges()

	# ---- Boundary 1: game boot -------------------------------------
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var game = main_scene.instantiate()
	add_child(game)
	await _wait_frames(10)
	check("game_boots_to_menu", game != null and int(game.get("state")) == 0,
		"state=%s" % str(game.get("state")))

	# ---- Boundary 2: Phase 05 assets exist and validate ------------
	var problems := AssetRegistry.validate()
	check("phase05_asset_registry_valid", problems.is_empty(),
		"problems=%s" % str(problems.size()))

	# ---- Boundary 3: autonomous start on a generated level ---------
	game.start_autonomous(20250)
	await _wait_frames(10)
	check("autonomous_starts_endless", int(game.get("state")) == 1
		and bool(game.get("endless_active"))
		and game.get("autonomous_controller") != null)
	var gen: Dictionary = game.get("_current_generated")
	var level: Dictionary = gen.get("level", {})
	check("generated_level_present", not gen.is_empty()
		and gen.has("level") and level.has("seed"),
		"seed=%s meta=%s" % [str(level.get("seed", null)),
			str((gen.get("meta", {}) as Dictionary).get("seed", null))])
	var dm := DifficultyManager.new()
	var diff: Dictionary = dm.profile_for(int(level.get("level_number", 1)))
	var verdict := LevelValidator.new().validate(level, diff)
	check("generated_level_revalidates", bool(verdict.get("valid", false)),
		"errors=%s" % str(verdict.get("errors", [])))

	# ---- Boundary 4: Phase 05 audio library feeds the mix plan -----
	var world := str(level.get("world", ""))
	var mixer := AudioMixer.new(EncodingConfig.preset_720p(30))
	var plan := mixer.plan_mix(6.0, world)
	var plan_paths_ok := true
	for track_v in plan.get("tracks", []):
		if not FileAccess.file_exists(str((track_v as Dictionary).get("path", ""))):
			plan_paths_ok = false
	check("phase05_audio_plan_uses_library", int(plan.get("tracks", []).size()) >= 2
		and not bool(plan.get("silent", true)) and plan_paths_ok,
		"world=%s tracks=%d skipped=%s" % [world,
			int(plan.get("tracks", []).size()), str(plan.get("skipped", []))])

	# ---- Boundary 5: autonomous gameplay, both modes ---------------
	Engine.time_scale = 3.0
	var ac: Node = game.get("autonomous_controller")
	var start_ctrl: Node3D = game.call("active_controller")
	var start_z := start_ctrl.global_position.z
	var saw_character := false
	var saw_vehicle := false
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline:
		await _wait_frames(15)
		if str(game.get("mode")) == "vehicle":
			saw_vehicle = true
		else:
			saw_character = true
		if saw_character and saw_vehicle:
			break
	var stats: Dictionary = ac.call("stats")
	var travelled := start_z - (game.call("active_controller") as Node3D).global_position.z
	print("MEASURED gameplay: modes character=%s vehicle=%s switches=%d decisions=%d levels_completed=%d travelled=%.1f" % [
		saw_character, saw_vehicle, int(stats.get("switches", 0)),
		int(stats.get("decisions", 0)), int(stats.get("levels_completed", 0)),
		travelled])
	check("gameplay_character_mode", saw_character)
	check("gameplay_vehicle_mode", saw_vehicle)
	check("gameplay_mode_switches", int(stats.get("switches", 0)) >= 1,
		"switches=%d" % int(stats.get("switches", 0)))
	check("gameplay_ai_decisions", int(stats.get("decisions", 0)) > 0,
		"decisions=%d" % int(stats.get("decisions", 0)))
	check("gameplay_progress", travelled > 50.0
		or int(stats.get("levels_completed", 0)) >= 1,
		"travelled=%.1f levels=%d" % [travelled, int(stats.get("levels_completed", 0))])
	Engine.time_scale = 1.0

	# ---- Boundary 6: Phase 06 capture + render ----------------------
	var cfg := EncodingConfig.preset_720p(15)
	cfg.output_dir = _recordings_root().path_join("run_e2e")
	var renderer = game.setup_broadcast(cfg)
	check("renderer_created", renderer != null)
	renderer.start_recording()
	for i in 6:
		await get_tree().create_timer(1.0).timeout
	var result: Dictionary = renderer.stop_and_render()
	var path := str(result.get("path", ""))
	print("MEASURED render: frames=%d capture_fps=%.2f encode_fps=%.2f game_fps=%.1f sync=%.3f" % [
		int(result.get("frames", 0)), float(result.get("capture_fps", 0.0)),
		float(renderer.perf.get("encode_fps", 0.0)),
		float(renderer.perf.get("game_fps", 0.0)),
		float(result.get("av_sync_offset", -1.0))])
	check("render_segment_valid", bool(result.get("valid", false)),
		"issues=%s" % str(result.get("issues", [])))
	check("render_frames_captured", int(result.get("frames", 0)) >= 10,
		"frames=%d" % int(result.get("frames", 0)))
	check("render_file_exists", path != "" and FileAccess.file_exists(path), path)
	var ff := FFmpegManager.new(cfg)
	var probe := ff.validate(path, cfg, true)
	check("render_probe_h264_aac", bool(probe.get("valid", false)),
		"issues=%s" % str(probe.get("issues", [])))
	check("render_av_sync", float(probe.get("av_sync_offset", 99.0)) < 0.5,
		"sync=%.3f" % float(probe.get("av_sync_offset", 99.0)))

	# ---- Boundary 7: capture health monitoring evaluates ------------
	var health_eval: Dictionary = (renderer.get("health") as RefCounted).call(
		"evaluate", renderer.perf)
	print("MEASURED capture_health: %s" % str(health_eval))
	check("capture_health_evaluates", not health_eval.is_empty()
		and health_eval.has("issues"))

	# ---- Boundary 8: Phase 07 stream PREPARE (local ingest only) ----
	var runtime := ProjectSettings.globalize_path("user://e2e_stream_runtime")
	var scfg := StreamConfig.new(EncodingConfig.preset_720p(30))
	scfg.apply_environment()
	scfg.lock_dir = runtime
	check("stream_config_from_env", scfg.has_stream_key()
		and scfg.ingest_base.begins_with("rtmp://127.0.0.1"),
		"ingest=%s" % scfg.safe_url())
	var sm := StreamManager.new()
	sm.name = "E2EStreamManager"
	add_child(sm)
	var admin := StreamAdmin.new(sm)
	admin.set_admin_token(admin_token)
	var spec := {"video_file": path, "frames_pattern": "", "audio_path": ""}
	var prep := admin.prepare_stream(spec, scfg)
	check("stream_prepare_ok", bool(prep.get("ok", false)),
		"errors=%s" % str(prep.get("errors", [])))
	check("stream_prepared_no_process", sm.state == StreamManager.STATE_PREPARED
		and sm.pid == -1,
		"state=%s pid=%d" % [sm.state, sm.pid])
	var stream_health := admin.check_health()
	check("stream_health_snapshot", str(stream_health.get("state", "")) == "prepared",
		"state=%s" % str(stream_health.get("state", "")))

	# ---- Boundary 9: public-start safeguard --------------------------
	var scfg2 := StreamConfig.new(EncodingConfig.preset_720p(30))
	scfg2.apply_environment()
	scfg2.visibility = "public"
	scfg2.lock_dir = runtime
	var sm2 := StreamManager.new()
	sm2.name = "E2EStreamManagerPublic"
	add_child(sm2)
	var admin2 := StreamAdmin.new(sm2)
	admin2.set_admin_token(admin_token)
	admin2.prepare_stream(spec, scfg2)
	var refused := admin2.start_stream(admin_token)  # no confirmation flag
	check("public_start_refused_without_confirmation",
		not bool(refused.get("ok", true))
		and str(refused.get("error", "")) == "public_confirmation_required"
		and sm2.pid == -1 and sm2.state == StreamManager.STATE_PREPARED,
		"result=%s" % str(refused))

	print("INTEGRATION_CHAIN_DONE failures=%d" % failures)
	get_tree().quit(mini(failures, 125))
