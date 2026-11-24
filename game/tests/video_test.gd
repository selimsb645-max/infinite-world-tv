extends Node
## Headless test suite for INFINITE WORLD TV Phase 06 (automated
## video production) — the logic half: config, ffmpeg command
## building and validation, audio mix planning/rendering, segment
## finalization and interrupted-recording recovery, storage caps,
## health evaluation and bounded recovery. The real-pixel half
## (viewport capture under Xvfb) is video_capture_test.gd.
## Run: godot --headless --path game res://tests/VideoTest.tscn
## Prints PASS/FAIL per check and VIDEO_LOGIC_DONE failures=N.

var failures: int = 0

const TMP := "user://video_test_tmp"

func check(test_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
	else:
		failures += 1
		print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func _ready() -> void:
	print("VIDEO_LOGIC_START")
	_clean_tmp()
	_test_config()
	_test_ffmpeg()
	_test_audio_mixer()
	_test_segments()
	_test_storage()
	_test_health()
	_test_recovery()
	_test_overlay()
	_test_camera()
	await _test_capture_manager_headless()
	_clean_tmp()
	print("VIDEO_LOGIC_DONE failures=%d" % failures)
	get_tree().quit(mini(failures, 125))

func _tmp_dir() -> String:
	return ProjectSettings.globalize_path(TMP)

func _clean_tmp() -> void:
	_remove_recursive(_tmp_dir())
	DirAccess.make_dir_recursive_absolute(_tmp_dir())

func _remove_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for name in d.get_files():
		d.remove(name)
	for sub in d.get_directories():
		_remove_recursive(path.path_join(sub))
	DirAccess.remove_absolute(path)

func _write_file(path: String, bytes: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var buffer := PackedByteArray()
	buffer.resize(bytes)
	f.store_buffer(buffer)
	f.close()

func _touch_old(path: String, when: String) -> void:
	OS.execute("touch", PackedStringArray(["-d", when, path]))

# --- EncodingConfig ---------------------------------------------------

func _test_config() -> void:
	var hd := EncodingConfig.preset_1080p()
	check("config_1080p_dims", hd.width == 1920 and hd.height == 1080)
	check("config_1080p_valid", hd.is_valid())
	check("config_720p_dims", EncodingConfig.preset_720p().resolution() == Vector2i(1280, 720))
	var fb := EncodingConfig.preset_1080p(60).fallback()
	check("config_fallback_720p30", fb.width == 1280 and fb.height == 720 and fb.fps == 30)
	check("config_fallback_keeps_output", fb.output_dir == hd.output_dir)
	var bad := EncodingConfig.preset_720p()
	bad.width = 721  # odd width is invalid for yuv420p
	check("config_invalid_detected", not bad.is_valid())
	check("config_summary_mentions_res", hd.summary().contains("1920x1080@30"))

# --- FFmpegManager ----------------------------------------------------

func _test_ffmpeg() -> void:
	var cfg := EncodingConfig.preset_720p(30)
	var ff := FFmpegManager.new(cfg)
	check("ffmpeg_available", ff.is_available())
	var args := ff.build_encode_args("frames/frame_%06d.png", "mix.wav",
		"out.partial.mp4", cfg, 4.0)
	var joined := " ".join(args)
	check("encode_args_h264", joined.contains("libx264"))
	check("encode_args_aac", joined.contains("aac"))
	check("encode_args_yuv420p", joined.contains("yuv420p"))
	check("encode_args_bitrate", joined.contains("4000k"))
	check("encode_args_duration", joined.contains("-t 4.000"))
	check("streaming_blocked_by_default", not ff.streaming_allowed(cfg))
	cfg.rtmp_url = "rtmp://example.invalid/live/key"
	check("streaming_blocked_without_enable", not ff.streaming_allowed(cfg))
	cfg.rtmp_enabled = true
	check("streaming_allowed_when_enabled", ff.streaming_allowed(cfg))
	var rtmp := " ".join(ff.build_rtmp_args("frames/frame_%06d.png", "mix.wav", cfg))
	check("rtmp_args_flv_tail", rtmp.ends_with("-f flv rtmp://example.invalid/live/key"))
	cfg.rtmp_enabled = false
	# A real encode of generated frames + probe validation.
	var dir := _tmp_dir().path_join("ff")
	DirAccess.make_dir_recursive_absolute(dir)
	var gen := ff.run(PackedStringArray([
		"-y", "-f", "lavfi", "-i", "testsrc=size=1280x720:rate=30:duration=1",
		"-c:v", "libx264", "-pix_fmt", "yuv420p", dir.path_join("clip.mp4")]))
	check("ffmpeg_testsrc_encode", int(gen["exit_code"]) == 0)
	var verdict := ff.validate(dir.path_join("clip.mp4"), cfg, false)
	check("validate_generated_clip", bool(verdict["valid"]),
		"issues=%s" % str(verdict["issues"]))
	var verdict_audio := ff.validate(dir.path_join("clip.mp4"), cfg, true)
	check("validate_detects_missing_audio",
		not bool(verdict_audio["valid"]) and verdict_audio["issues"].has("no_audio_stream"))
	var missing := ff.validate(dir.path_join("nope.mp4"), cfg, false)
	check("validate_missing_file", not bool(missing["valid"]))

# --- AudioMixer ---------------------------------------------------------

func _test_audio_mixer() -> void:
	var cfg := EncodingConfig.preset_720p(30)
	var mixer := AudioMixer.new(cfg)
	var plan := mixer.plan_mix(2.0, "Green Valley", [
		{"clip": "collect", "at": 0.5},
		{"clip": "does_not_exist", "at": 1.0},
	])
	var clips: Array = []
	for track_v in plan["tracks"]:
		clips.append(str((track_v as Dictionary)["clip"]))
	check("mix_has_music", clips.has("music"))
	check("mix_has_world_ambience", clips.has("ambience_green_valley"))
	check("mix_has_event", clips.has("collect"))
	check("mix_skips_missing", plan["skipped"].has("does_not_exist"))
	check("mix_not_silent", not bool(plan["silent"]))
	var music_gain := -999.0
	for track_v in plan["tracks"]:
		var track: Dictionary = track_v
		if str(track["clip"]) == "music":
			music_gain = float(track["gain_db"])
	check("mix_music_gain_from_config", is_equal_approx(music_gain, cfg.music_db))
	var ff := FFmpegManager.new(cfg)
	var out := _tmp_dir().path_join("mix.wav")
	var rendered := mixer.render_mix(plan, out, ff)
	check("mix_render_ok", bool(rendered["ok"]))
	var info := ff.probe(out)
	var audio_stream: Dictionary = {}
	for stream_v in info.get("streams", []):
		if (stream_v as Dictionary).get("codec_type", "") == "audio":
			audio_stream = stream_v
	check("mix_output_is_audio", not audio_stream.is_empty())
	var dur := float(info.get("format", {}).get("duration", 0.0))
	check("mix_duration_matches_segment", dur > 1.8 and dur < 2.2, "dur=%.2f" % dur)
	var silent_plan := mixer.plan_mix(1.0, "Nowhere Land", [])
	# Music still exists, so force a truly empty plan by hand:
	silent_plan["tracks"] = []
	silent_plan["silent"] = true
	var silent_out := _tmp_dir().path_join("silence.wav")
	var silent_render := mixer.render_mix(silent_plan, silent_out, ff)
	check("mix_silent_render_ok", bool(silent_render["ok"]) and bool(silent_render["silent"]))

# --- VideoSegmentManager ------------------------------------------------

func _test_segments() -> void:
	var sm := VideoSegmentManager.new()
	var name := sm.segment_basename(7, {"year": 2026, "month": 11, "day": 24,
		"hour": 9, "minute": 5, "second": 3})
	check("segment_name_format", name == "iwtv_20261124_090503_seg007", name)
	var dir := _tmp_dir().path_join("segments")
	DirAccess.make_dir_recursive_absolute(dir)
	var final := sm.final_path(dir, 1)
	var partial := sm.partial_path(final)
	check("partial_path_suffix", partial.ends_with(".partial.mp4"))
	check("finalize_missing_refused", sm.finalize_segment(partial) == "")
	_write_file(partial, 0)
	check("finalize_empty_refused", sm.finalize_segment(partial) == "")
	_write_file(partial, 2048)
	var promoted := sm.finalize_segment(partial)
	check("finalize_promotes", promoted == final and FileAccess.file_exists(final))
	check("list_segments_finds_final", sm.list_segments(dir).size() == 1)
	# Interrupted recovery: one garbage partial (discarded) and one
	# real encoded partial (recovered).
	var garbage := dir.path_join("iwtv_20260101_000000_seg002.partial.mp4")
	_write_file(garbage, 512)
	var ff := FFmpegManager.new(EncodingConfig.preset_720p(30))
	var real_partial := dir.path_join("iwtv_20260101_000100_seg003.partial.mp4")
	ff.run(PackedStringArray([
		"-y", "-f", "lavfi", "-i", "testsrc=size=1280x720:rate=30:duration=1",
		"-c:v", "libx264", "-pix_fmt", "yuv420p", real_partial]))
	check("interrupted_found", sm.find_interrupted(dir).size() == 2)
	var actions := sm.recover_interrupted(dir, ff, EncodingConfig.preset_720p(30))
	var by_action := {}
	for action_v in actions:
		var action: Dictionary = action_v
		by_action[str(action["path"]).get_file()] = str(action["action"])
	check("interrupted_garbage_discarded",
		by_action.get(garbage.get_file(), "") == "discarded"
		and not FileAccess.file_exists(garbage))
	check("interrupted_valid_recovered",
		by_action.get(real_partial.get_file(), "") == "recovered"
		and FileAccess.file_exists(real_partial.replace(".partial.mp4", ".mp4")))

# --- StorageManager -----------------------------------------------------

func _test_storage() -> void:
	var sm := VideoSegmentManager.new()
	var st := StorageManager.new()
	var dir := _tmp_dir().path_join("storage")
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 3:
		var path := dir.path_join("seg_%d.mp4" % i)
		_write_file(path, 100_000)
		_touch_old(path, "2026-01-0%d 10:00" % (i + 1))
	var usage := st.usage(dir)
	check("storage_usage_counts", int(usage["segments"]) == 3
		and int(usage["bytes"]) == 300_000)
	var cfg := EncodingConfig.preset_720p(30)
	cfg.max_segments = 2
	cfg.max_storage_mb = 100.0
	var result := st.enforce(dir, cfg, sm)
	check("storage_count_cap_deletes_oldest",
		result["deleted"].size() == 1
		and str(result["deleted"][0]).ends_with("seg_0.mp4")
		and st.usage(dir)["segments"] == 2)
	cfg.max_segments = 99
	cfg.max_storage_mb = 0.15  # ~150 KB: only one 100 KB file fits
	result = st.enforce(dir, cfg, sm)
	check("storage_size_cap_enforced", float(st.usage(dir)["mb"]) <= 0.15,
		"mb=%.3f" % float(st.usage(dir)["mb"]))
	# Retention: the remaining file is from January; 1-hour retention
	# must remove it — but never the protected path.
	cfg.max_storage_mb = 100.0
	cfg.retention_sec = 3600.0
	var remaining := sm.list_segments(dir)
	if remaining.size() > 0:
		var protected := str(remaining[0]["path"])
		result = st.enforce(dir, cfg, sm, protected)
		check("storage_retention_spares_protected",
			FileAccess.file_exists(protected))

# --- CaptureHealthMonitor ----------------------------------------------

func _test_health() -> void:
	var hm := CaptureHealthMonitor.new()
	var good := hm.evaluate({
		"recording_sec": 10.0, "target_fps": 30.0, "capture_fps": 29.0,
		"frames_expected": 300, "frames_captured": 295,
		"encode_exit_code": 0, "encode_fps": 60.0, "output_valid": true,
		"audio_expected": true, "audio_present": true,
		"av_sync_offset": 0.05, "storage_ok": true})
	check("health_good_is_healthy", bool(good["healthy"]))
	var bad := hm.evaluate({
		"recording_sec": 10.0, "target_fps": 30.0, "capture_fps": 5.0,
		"frames_expected": 300, "frames_captured": 50,
		"encode_exit_code": 1, "encode_fps": 0.0, "output_valid": false,
		"audio_expected": true, "audio_present": false,
		"av_sync_offset": 2.0, "storage_ok": false})
	var issues: Array = bad["issues"]
	check("health_detects_missing_frames", issues.has("MISSING_FRAMES"))
	check("health_detects_low_fps", issues.has("LOW_CAPTURE_FPS"))
	check("health_detects_encode_failure", issues.has("ENCODE_FAILURE"))
	check("health_detects_audio_loss", issues.has("AUDIO_LOSS"))
	check("health_detects_sync_drift", issues.has("AV_SYNC_DRIFT"))
	check("health_detects_storage", issues.has("STORAGE_LOW"))
	check("health_bad_not_healthy", not bool(bad["healthy"]))

# --- VideoRecoveryManager ----------------------------------------------

func _test_recovery() -> void:
	var rm := VideoRecoveryManager.new()
	rm.max_attempts = 3
	check("recovery_action_encode", rm.plan_action("ENCODE_FAILURE") == "reencode")
	check("recovery_action_invalid", rm.plan_action("INVALID_OUTPUT") == "reencode_fallback")
	check("recovery_action_audio", rm.plan_action("AUDIO_LOSS") == "reencode_without_audio")
	check("recovery_action_storage", rm.plan_action("STORAGE_LOW") == "cleanup_storage")
	check("recovery_action_capture", rm.plan_action("MISSING_FRAMES") == "restart_capture")
	# ENCODE_FAILURE has 2 attempts left; spend them, then give up.
	rm.plan_action("ENCODE_FAILURE")
	rm.plan_action("ENCODE_FAILURE")
	check("recovery_bounded_gives_up", rm.plan_action("ENCODE_FAILURE") == "give_up")
	check("recovery_exhausted_flag", rm.exhausted("ENCODE_FAILURE"))
	check("recovery_other_issue_unaffected", rm.can_attempt("STORAGE_LOW"))
	rm.reset()
	check("recovery_reset_restores", rm.can_attempt("ENCODE_FAILURE"))

# --- BroadcastOverlayManager ---------------------------------------------

func _test_overlay() -> void:
	var overlay := BroadcastOverlayManager.new(true, "INFINITE WORLD TV")
	add_child(overlay)
	overlay.set_world("Neon City")
	overlay.set_level("Level 3")
	overlay.set_score(250)
	overlay.set_mode("Vehicle")
	overlay.set_progress(0.4)
	var snap := overlay.snapshot_state()
	check("overlay_state_roundtrip",
		snap["world"] == "Neon City" and snap["level"] == "Level 3"
		and int(snap["score"]) == 250 and snap["mode"] == "Vehicle"
		and is_equal_approx(float(snap["progress"]), 0.4))
	check("overlay_branding_on", bool(snap["branding"]))
	var plain := BroadcastOverlayManager.new(false)
	add_child(plain)
	check("overlay_branding_off", not bool(plain.snapshot_state()["branding"]))
	overlay.queue_free()
	plain.queue_free()

# --- Camera --------------------------------------------------------------

func _test_camera() -> void:
	var rig := CameraController.new()
	add_child(rig)
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, 0)
	rig.set_target(target, "character")
	rig.snap_to_target()
	var base_pos := rig.global_position
	rig.set_distance_scale(1.5)
	rig.snap_to_target()
	check("camera_distance_scale_applies",
		rig.global_position.length() > base_pos.length() * 1.4,
		"base=%.2f scaled=%.2f" % [base_pos.length(), rig.global_position.length()])
	rig.set_distance_scale(99.0)
	check("camera_distance_scale_clamped", is_equal_approx(rig.distance_scale, 1.6))
	var ctrl := CameraCaptureController.new()
	add_child(ctrl)
	check("camera_ctrl_unbound_safe", not ctrl.is_horizon_stable())
	ctrl.bind(rig, null)
	check("camera_ctrl_null_game_safe", ctrl.stats().has("horizon_stable"))
	rig.queue_free()
	target.queue_free()
	ctrl.queue_free()

# --- GameCaptureManager (headless: no real pixels, must stay safe) -------

func _test_capture_manager_headless() -> void:
	var cm := GameCaptureManager.new(EncodingConfig.preset_720p(30))
	add_child(cm)
	var dir := _tmp_dir().path_join("frames")
	cm.begin(dir)
	check("capture_begin_state", cm.capturing and DirAccess.dir_exists_absolute(dir))
	await get_tree().create_timer(0.4).timeout
	var stats := cm.end()
	check("capture_end_state", not cm.capturing and stats.has("frames_captured"))
	check("capture_frames_dir_pattern", cm.frames_pattern().ends_with("frame_%06d.png"))
	cm.queue_free()
