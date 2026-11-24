extends Node
## Real-pixel test suite for INFINITE WORLD TV Phase 06 — run under
## Xvfb (NOT --headless; the dummy driver has no pixels):
##   xvfb-run -a godot --path game res://tests/VideoCaptureTest.tscn
## Loads the real game, lets the Phase 04 autopilot play, records
## real viewport frames through the full Phase 06 pipeline and
## validates the encoded MP4s with ffprobe. Prints measured
## performance (this VM has no GPU: llvmpipe software rendering).
## Prints PASS/FAIL per check and VIDEO_CAPTURE_DONE failures=N.

var failures: int = 0

func check(test_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
	else:
		failures += 1
		print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func _recordings_root() -> String:
	return ProjectSettings.globalize_path("res://../recordings")

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _image_hash(image: Image) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(image.get_data())
	return ctx.finish().hex_encode()

func _ready() -> void:
	print("VIDEO_CAPTURE_START")
	var root := _recordings_root()
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var game = main_scene.instantiate()
	add_child(game)
	await get_tree().create_timer(0.5).timeout
	game.start_autonomous(777)
	await get_tree().create_timer(1.5).timeout

	# ---- Run A: 720p end-to-end ------------------------------------
	var cfg_a := EncodingConfig.preset_720p(15)
	cfg_a.output_dir = root.path_join("run_a")
	var renderer = game.setup_broadcast(cfg_a)
	check("renderer_created", renderer != null)
	# Overlay must actually change the rendered pixels.
	var with_overlay := await _grab()
	renderer.overlay.visible = false
	await RenderingServer.frame_post_draw
	var without_overlay := await _grab()
	renderer.overlay.visible = true
	check("overlay_visible_in_frame",
		_image_hash(with_overlay) != _image_hash(without_overlay))
	check("overlay_state_live", renderer.overlay.snapshot_state()["world"] != "—",
		"world=%s" % renderer.overlay.snapshot_state()["world"])
	var game_fps_samples: Array = []
	renderer.start_recording()
	for i in 6:
		await get_tree().create_timer(1.0).timeout
		game_fps_samples.append(float(renderer.perf.get("game_fps", 0)))
	var result_a: Dictionary = renderer.stop_and_render()
	var avg_game_fps := 0.0
	for sample in game_fps_samples:
		avg_game_fps += float(sample)
	avg_game_fps /= maxf(float(game_fps_samples.size()), 1.0)
	print("MEASURED run_a: frames=%d capture_fps=%.2f encode_fps=%.2f encode_sec=%.2f game_fps=%.1f sync=%.3f recoveries=%s" % [
		int(result_a.get("frames", 0)), float(result_a.get("capture_fps", 0.0)),
		float(renderer.perf.get("encode_fps", 0.0)),
		float(result_a.get("encode_seconds", 0.0)), avg_game_fps,
		float(result_a.get("av_sync_offset", -1.0)),
		str(result_a.get("recoveries", []))])
	check("run_a_valid_segment", bool(result_a.get("valid", false)),
		"issues=%s" % str(result_a.get("issues", [])))
	check("run_a_frames_captured", int(result_a.get("frames", 0)) >= 25,
		"frames=%d" % int(result_a.get("frames", 0)))
	var path_a := str(result_a.get("path", ""))
	check("run_a_file_exists", path_a != "" and FileAccess.file_exists(path_a), path_a)
	var ff := FFmpegManager.new(cfg_a)
	var verdict_a := ff.validate(path_a, cfg_a, true)
	check("run_a_probe_h264_aac_720p", bool(verdict_a["valid"]),
		"issues=%s" % str(verdict_a["issues"]))
	check("run_a_duration_sane", float(verdict_a.get("duration", 0.0)) > 1.5
		and float(verdict_a.get("duration", 0.0)) < 8.0,
		"dur=%.2f" % float(verdict_a.get("duration", 0.0)))
	check("run_a_av_sync", float(verdict_a.get("av_sync_offset", 99.0)) < 0.5,
		"sync=%.3f" % float(verdict_a.get("av_sync_offset", 99.0)))

	# ---- Run B: 1080p configuration --------------------------------
	var cfg_b := EncodingConfig.preset_1080p(30)
	cfg_b.output_dir = root.path_join("run_b")
	var renderer_b := VideoRenderer.new()
	renderer_b.name = "VideoRenderer1080"
	game.add_child(renderer_b)
	renderer_b.setup(game, cfg_b)
	renderer_b.start_recording()
	await get_tree().create_timer(3.0).timeout
	var result_b: Dictionary = renderer_b.stop_and_render()
	print("MEASURED run_b: frames=%d capture_fps=%.2f encode_sec=%.2f fallback=%s" % [
		int(result_b.get("frames", 0)), float(result_b.get("capture_fps", 0.0)),
		float(result_b.get("encode_seconds", 0.0)),
		str(result_b.get("used_fallback", false))])
	var path_b := str(result_b.get("path", ""))
	var verdict_b := ff.validate(path_b, cfg_b, true)
	check("run_b_1080p_output", path_b != "" and bool(verdict_b["valid"]),
		"issues=%s" % str(verdict_b["issues"]))

	# ---- Run C: continuous segmentation (extended run) -------------
	var cfg_c := EncodingConfig.preset_720p(15)
	cfg_c.output_dir = root.path_join("run_c")
	cfg_c.segment_duration_sec = 3.0
	var renderer_c := VideoRenderer.new()
	renderer_c.name = "VideoRendererSegments"
	game.add_child(renderer_c)
	renderer_c.setup(game, cfg_c)
	renderer_c.start_continuous()
	await get_tree().create_timer(13.0).timeout
	renderer_c.stop_continuous()
	var segments := VideoSegmentManager.new().list_segments(cfg_c.output_dir)
	check("run_c_multiple_segments", segments.size() >= 2,
		"segments=%d" % segments.size())
	var all_valid := true
	for seg_v in segments:
		var seg: Dictionary = seg_v
		if not bool(ff.validate(str(seg["path"]), cfg_c, true)["valid"]):
			all_valid = false
	check("run_c_segments_all_valid", all_valid and segments.size() > 0)
	print("MEASURED run_c: segments=%d total_size_mb=%.2f" % [
		segments.size(),
		float(StorageManager.new().usage(cfg_c.output_dir)["mb"])])

	# ---- Graceful misuse --------------------------------------------
	var idle := renderer_c.stop_and_render()
	check("stop_without_recording_safe",
		not bool(idle.get("valid", true)) and idle.get("issues", []).has("not_recording"))

	print("VIDEO_CAPTURE_DONE failures=%d" % failures)
	get_tree().quit(mini(failures, 125))
