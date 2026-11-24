class_name VideoRenderer
extends Node
## Phase 06 — the automated video production pipeline, orchestrating
## the other Phase 06 modules:
##
##   GameCaptureManager  -> PNG frame sequence at the configured rate
##   AudioMixer          -> music + world ambience + SFX events,
##                          mixed to the exact segment duration
##   FFmpegManager       -> H.264/AAC encode to .partial.mp4,
##                          ffprobe validation (codecs, resolution,
##                          fps, A/V sync)
##   VideoSegmentManager -> safe finalization (rename on valid only)
##   StorageManager      -> caps + retention enforced per segment
##   CaptureHealthMonitor-> named issues per segment
##   VideoRecoveryManager-> bounded recovery (re-encode, 720p
##                          fallback, audio-less encode, storage
##                          cleanup) — never an open-ended loop
##
## Recording is opt-in (GameManager.setup_broadcast()), exactly like
## Phase 04's start_autonomous(): nothing in the normal game changes
## until a recording is started. Streaming is NOT implemented here —
## EncodingConfig carries the RTMP settings for the later phase and
## streaming_allowed() stays false until then.

var config: EncodingConfig
var game: Node  # GameManager (untyped: avoids a cyclic dependency)
var ffmpeg: FFmpegManager
var mixer: AudioMixer
var segments: VideoSegmentManager
var storage: StorageManager
var health: CaptureHealthMonitor
var recovery: VideoRecoveryManager
var capture: GameCaptureManager
var camera_control: CameraCaptureController
var overlay: BroadcastOverlayManager

var recording: bool = false
var continuous: bool = false
var segment_index: int = 0
var last_result: Dictionary = {}
var perf: Dictionary = {}
var recovery_log: Array = []

var _frames_dir: String = ""
var _world: String = ""
var _segment_events: Array = []
var _encode_fps: float = 0.0

func setup(game_manager: Node, cfg: EncodingConfig = null) -> void:
	game = game_manager
	config = cfg if cfg != null else EncodingConfig.preset_720p()
	ffmpeg = FFmpegManager.new(config)
	mixer = AudioMixer.new(config)
	segments = VideoSegmentManager.new()
	storage = StorageManager.new()
	health = CaptureHealthMonitor.new()
	recovery = VideoRecoveryManager.new()
	capture = GameCaptureManager.new(config)
	capture.name = "GameCaptureManager"
	add_child(capture)
	camera_control = CameraCaptureController.new()
	camera_control.name = "CameraCaptureController"
	add_child(camera_control)
	camera_control.bind(game_manager.get("camera_rig"), game_manager)
	overlay = BroadcastOverlayManager.new(config.branding_enabled, config.channel_name)
	overlay.name = "BroadcastOverlay"
	add_child(overlay)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(config.output_dir))
	# Startup housekeeping: judge anything a previous crash left
	# behind, and enforce the storage caps before recording a byte.
	for action in segments.recover_interrupted(config.output_dir, ffmpeg, config):
		recovery_log.append("startup:%s:%s" % [action["action"], action["path"]])
	storage.enforce(config.output_dir, config, segments)
	# Reflect the game's current state on the overlay immediately
	# (GameManager._update_hud forwards to us when we are its
	# registered broadcast renderer).
	if game != null and game.get("broadcast") == self:
		game.call("_update_hud")

func update_overlay(score_value: int, mode_text: String,
		level_text: String, world: String) -> void:
	if overlay == null:
		return
	overlay.set_score(score_value)
	overlay.set_mode(mode_text)
	overlay.set_level(level_text)
	overlay.set_world(world)

func set_progress(value: float) -> void:
	if overlay != null:
		overlay.set_progress(value)

## Called by GameManager hooks (collect / finish / mode switch) so
## the segment's audio mix carries the sounds that actually happened.
func note_sfx(clip: String) -> void:
	if recording:
		_segment_events.append({"clip": clip, "at": capture.elapsed_sec()})

func start_recording() -> void:
	if recording or capture == null:
		return
	segment_index += 1
	_frames_dir = config.output_dir.path_join("frames_seg%03d" % segment_index)
	_clear_dir(_frames_dir)
	_segment_events.clear()
	_world = str(game.get("environment_manager").get("current_theme")) \
		if game != null else ""
	capture.begin(_frames_dir)
	recording = true

func start_continuous() -> void:
	continuous = true
	start_recording()

func stop_continuous() -> void:
	continuous = false
	if recording:
		stop_and_render()

func _process(_delta: float) -> void:
	perf = {
		"game_fps": Engine.get_frames_per_second(),
		"capture_fps": capture.capture_fps() if capture != null else 0.0,
		"encode_fps": _encode_fps,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"ram_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"gpu": "unavailable (no GPU on this machine)",
	}
	if continuous and recording \
			and capture.elapsed_sec() >= config.segment_duration_sec:
		stop_and_render()
		if continuous:
			start_recording()

## Stops capture and runs the whole render chain for the segment.
## Returns (and stores) the result dictionary; see the module doc
## for the fields. Never throws: every failure lands in the result.
func stop_and_render() -> Dictionary:
	if not recording:
		return {"valid": false, "issues": ["not_recording"]}
	recording = false
	var cap_stats := capture.end()
	var frames := int(cap_stats["frames_captured"])
	var result: Dictionary = {
		"segment_index": segment_index,
		"frames": frames,
		"capture_fps": float(cap_stats["capture_fps"]),
		"recording_sec": float(cap_stats["elapsed_sec"]),
		"valid": false, "issues": [], "path": "",
		"used_fallback": false, "recoveries": [],
	}
	if frames == 0:
		result["issues"] = ["no_frames"]
		last_result = result
		return result
	var duration := float(frames) / float(config.fps)
	var final := segments.final_path(config.output_dir, segment_index)
	var partial := segments.partial_path(final)
	var audio_path := config.output_dir.path_join("seg%03d_mix.wav" % segment_index)
	var plan := mixer.plan_mix(duration, _world, _segment_events)
	var mix_result := mixer.render_mix(plan, audio_path, ffmpeg)
	var audio_ok := bool(mix_result["ok"])
	var audio_dropped := false  # recovery deliberately encoded video-only
	var encode := _encode(partial, audio_path if audio_ok else "", config, duration)
	var verdict := ffmpeg.validate(partial, config, true)
	_apply_verdict(result, verdict, encode, partial, final)
	result["av_sync_offset"] = float(verdict.get("av_sync_offset", -1.0))
	# Health + bounded recovery.
	var stats := _health_stats(result, cap_stats, encode, verdict, audio_ok, audio_dropped)
	var verdict_health := health.evaluate(stats)
	var guard := 0
	while not bool(verdict_health["healthy"]) and guard < 6:
		guard += 1
		var acted := false
		for issue_v in verdict_health["issues"]:
			var issue := str(issue_v)
			if not recovery.can_attempt(issue):
				continue
			var action := recovery.plan_action(issue)
			result["recoveries"].append("%s:%s" % [issue, action])
			acted = true
			match action:
				"reencode":
					encode = _encode(partial, audio_path if audio_ok else "",
						config, duration)
					verdict = ffmpeg.validate(partial, config, true)
				"reencode_fallback", "fallback_resolution":
					var fb := config.fallback()
					encode = _encode(partial, audio_path if audio_ok else "",
						fb, duration)
					verdict = ffmpeg.validate(partial, fb, true)
					if bool(verdict["valid"]):
						result["used_fallback"] = true
				"reencode_without_audio":
					encode = _encode(partial, "", config, duration)
					verdict = ffmpeg.validate(partial, config, false)
					if bool(verdict["valid"]):
						audio_dropped = true
				"cleanup_storage":
					storage.enforce(config.output_dir, config, segments)
				"restart_capture":
					# A finished segment's frames cannot be re-shot;
					# the capture session itself restarts cleanly at
					# the next segment boundary (capture.begin()).
					recovery_log.append("capture session restarts at next segment")
			_apply_verdict(result, verdict, encode, partial, final)
			result["av_sync_offset"] = float(verdict.get("av_sync_offset", -1.0))
		if not acted:
			break
		stats = _health_stats(result, cap_stats, encode, verdict, audio_ok, audio_dropped)
		verdict_health = health.evaluate(stats)
	result["issues"] = verdict_health["issues"]
	result["healthy"] = bool(verdict_health["healthy"])
	result["encode_fps"] = _encode_fps
	perf["encode_fps"] = _encode_fps
	# Storage caps last, protecting the segment we just made.
	if str(result["path"]) != "":
		storage.enforce(config.output_dir, config, segments, str(result["path"]))
		_clear_dir(_frames_dir)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(audio_path))
	last_result = result
	return result

func _encode(partial: String, audio_path: String,
		cfg: EncodingConfig, duration: float) -> Dictionary:
	var args := ffmpeg.build_encode_args(
		capture.frames_pattern(), audio_path, partial, cfg, duration)
	var run := ffmpeg.run(args)
	if float(run["seconds"]) > 0.0:
		_encode_fps = float(capture.frames_captured) / float(run["seconds"]) \
			if capture != null else 0.0
	return run

func _apply_verdict(result: Dictionary, verdict: Dictionary,
		encode: Dictionary, partial: String, final: String) -> void:
	result["encode_exit_code"] = int(encode.get("exit_code", -1))
	result["encode_seconds"] = float(encode.get("seconds", 0.0))
	if bool(verdict.get("valid", false)) and str(result["path"]) == "":
		var promoted := segments.finalize_segment(partial)
		if promoted != "":
			result["path"] = promoted
			result["valid"] = true
	elif bool(verdict.get("valid", false)):
		result["valid"] = true
	result["duration"] = float(verdict.get("duration", 0.0))

func _health_stats(result: Dictionary, cap_stats: Dictionary,
		encode: Dictionary, verdict: Dictionary, audio_ok: bool,
		audio_dropped: bool = false) -> Dictionary:
	var issues: Array = verdict.get("issues", [])
	return {
		"recording_sec": float(cap_stats["elapsed_sec"]),
		"target_fps": float(config.fps),
		"capture_fps": float(cap_stats["capture_fps"]),
		"frames_expected": int(cap_stats["frames_expected"]),
		"frames_captured": int(cap_stats["frames_captured"]),
		"encode_exit_code": int(encode.get("exit_code", -1)),
		"encode_fps": _encode_fps,
		"output_valid": bool(verdict.get("valid", false)),
		"audio_expected": true,
		"audio_present": audio_dropped
			or (audio_ok and not issues.has("no_audio_stream")),
		"av_sync_offset": float(verdict.get("av_sync_offset", 0.0)),
		"storage_ok": storage.headroom_ok(config.output_dir, config),
	}

func _clear_dir(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for name in d.get_files():
		d.remove(name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
