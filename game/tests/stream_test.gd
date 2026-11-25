extends Node
## Test suite for INFINITE WORLD TV Phase 07 (YouTube Live
## streaming & broadcast infrastructure) — config validation,
## secret handling and redaction, admin authorization, the public
## broadcast confirmation safeguard, and REAL streaming processes
## against a LOCAL RTMP listener (ffmpeg's own RTMP server on
## 127.0.0.1). No YouTube connection is made and no real stream key
## exists in these tests: the key below is an obvious fake, and the
## ingest is overridden to localhost for every process test.
## Run: godot --headless --path game res://tests/StreamTest.tscn
## Prints PASS/FAIL per check and STREAM_DONE failures=N.

var failures: int = 0

const TMP := "user://stream_test_tmp"
const FAKE_KEY := "FAKEKEY-test-7f3d9a-NOT-REAL"
const ADMIN := "test-admin-token"

var _managers: Array = []
var _listener_pids: Array = []
var _ff: FFmpegManager

func check(test_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
	else:
		failures += 1
		print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func _ready() -> void:
	print("STREAM_START")
	_ff = FFmpegManager.new()
	_clean_tmp()
	_generate_inputs()
	_test_config()
	_test_env_loading()
	_test_health_monitor()
	await _test_admin_and_prepare()
	await _test_local_stream_flow()
	await _test_public_confirmation()
	await _test_crash_recovery()
	await _test_network_interruption()
	await _test_reconnect_bounded()
	await _test_recovery_disabled()
	_test_redaction_everywhere()
	_cleanup_processes()
	_clean_tmp()
	print("STREAM_DONE failures=%d" % failures)
	get_tree().quit(mini(failures, 125))

# --- Helpers --------------------------------------------------------------

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

func _wait_until(callable: Callable, timeout_sec: float) -> bool:
	var waited := 0.0
	while waited < timeout_sec:
		if bool(callable.call()):
			return true
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	return bool(callable.call())

func _make_encoder() -> EncodingConfig:
	var enc := EncodingConfig.new()
	enc.width = 320
	enc.height = 240
	enc.fps = 24
	enc.video_bitrate_kbps = 400
	enc.audio_bitrate_kbps = 64
	enc.x264_preset = "ultrafast"
	return enc

func _make_config(port: int, with_key: bool = true) -> StreamConfig:
	var cfg := StreamConfig.new(_make_encoder())
	cfg.ingest_base = "rtmp://127.0.0.1:%d/live" % port
	if with_key:
		cfg.set_stream_key(FAKE_KEY)
	cfg.lock_dir = _tmp_dir().path_join("runtime_%d" % port)
	cfg.stall_timeout_sec = 8.0
	return cfg

func _input_spec() -> Dictionary:
	return {
		"frames_pattern": _tmp_dir().path_join("frames/frame_%06d.png"),
		"audio_path": _tmp_dir().path_join("tone.wav"),
	}

func _new_manager() -> StreamManager:
	var m := StreamManager.new()
	add_child(m)
	_managers.append(m)
	return m

func _start_listener(port: int, out_name: String) -> int:
	var out_path := _tmp_dir().path_join(out_name)
	var pid := OS.create_process("ffmpeg", PackedStringArray([
		"-hide_banner", "-loglevel", "error",
		"-f", "flv", "-listen", "1",
		"-i", "rtmp://127.0.0.1:%d/live/%s" % [port, FAKE_KEY],
		"-c", "copy", "-y", out_path]))
	_listener_pids.append(pid)
	return pid

func _kill(pid: int, sig: String = "-TERM") -> void:
	if pid > 0:
		OS.execute("kill", PackedStringArray([sig, str(pid)]))

func _generate_inputs() -> void:
	var frames_dir := _tmp_dir().path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var gen := _ff.run(PackedStringArray([
		"-y", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=24:duration=10",
		frames_dir.path_join("frame_%06d.png")]))
	check("inputs_frames_generated", int(gen["exit_code"]) == 0)
	var tone := _ff.run(PackedStringArray([
		"-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=10",
		_tmp_dir().path_join("tone.wav")]))
	check("inputs_audio_generated", int(tone["exit_code"]) == 0)

# --- StreamConfig -----------------------------------------------------------

func _test_config() -> void:
	var cfg := _make_config(11940)
	check("cfg_default_keyframe_is_2", cfg.keyframe_interval_sec == 2)
	check("cfg_default_ingest_rtmps",
		StreamConfig.new().ingest_base.begins_with("rtmps://"))
	check("cfg_valid_with_key", bool(cfg.validate()["valid"]))
	var no_key := _make_config(11940, false)
	var verdict := no_key.validate()
	check("cfg_missing_key_flagged", not bool(verdict["valid"])
		and verdict["errors"].has("missing_credentials:" + StreamConfig.ENV_STREAM_KEY),
		str(verdict["errors"]))
	var bad_gop := _make_config(11940)
	bad_gop.keyframe_interval_sec = 5  # YouTube: never exceed 4 s
	check("cfg_keyframe_over_4_invalid", not bool(bad_gop.validate()["valid"]))
	var bad_ingest := _make_config(11940)
	bad_ingest.ingest_base = "http://example.com/live"
	check("cfg_bad_ingest_invalid", not bool(bad_ingest.validate()["valid"]))
	check("redact_masks_key",
		not cfg.redact("POST rtmps://a.rtmps.youtube.com/live2/" + FAKE_KEY + " 403")
			.contains(FAKE_KEY))
	check("summary_hides_key", not cfg.summary().contains(FAKE_KEY)
		and cfg.summary().contains("key=set"))
	check("safe_url_hides_key", not cfg.safe_url().contains(FAKE_KEY))
	check("full_url_carries_key_for_process",
		cfg.full_url().ends_with(FAKE_KEY))
	var backoff := _make_config(11940)
	backoff.reconnect_base_delay_sec = 2.0
	backoff.reconnect_max_delay_sec = 60.0
	check("backoff_sequence_doubles",
		is_equal_approx(backoff.backoff_delay(1), 2.0)
		and is_equal_approx(backoff.backoff_delay(2), 4.0)
		and is_equal_approx(backoff.backoff_delay(3), 8.0)
		and is_equal_approx(backoff.backoff_delay(4), 16.0))
	check("backoff_capped", is_equal_approx(backoff.backoff_delay(10), 60.0))

func _test_env_loading() -> void:
	OS.set_environment(StreamConfig.ENV_STREAM_KEY, FAKE_KEY)
	var cfg := StreamConfig.new(_make_encoder())
	cfg.apply_environment()
	check("env_var_key_loaded", cfg.has_stream_key())
	OS.set_environment(StreamConfig.ENV_STREAM_KEY, "")
	var env_path := _tmp_dir().path_join(".env")
	var f := FileAccess.open(env_path, FileAccess.WRITE)
	f.store_line(StreamConfig.ENV_STREAM_KEY + "=" + FAKE_KEY)
	f.store_line(StreamConfig.ENV_VISIBILITY + "=unlisted")
	f.close()
	var cfg2 := StreamConfig.new(_make_encoder())
	var loaded := cfg2.load_env_file(env_path)
	check("env_file_loaded", cfg2.has_stream_key()
		and cfg2.visibility == "unlisted"
		and loaded.has(StreamConfig.ENV_STREAM_KEY))
	check("env_file_missing_is_safe",
		StreamConfig.new().load_env_file(_tmp_dir().path_join("nope.env")).is_empty())

# --- StreamHealthMonitor ------------------------------------------------------

func _test_health_monitor() -> void:
	var path := _tmp_dir().path_join("progress.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("frame=100\nfps=24.0\nbitrate=1000.0kbits/s\ndrop_frames=0\ndup_frames=0\nprogress=continue\n")
	f.store_string("frame=480\nfps=23.9\nbitrate=2500.5kbits/s\ndrop_frames=3\ndup_frames=1\nprogress=continue\n")
	f.close()
	var block := StreamHealthMonitor.parse_progress_file(path)
	check("progress_parse_last_block",
		int(block.get("frame", 0)) == 480
		and is_equal_approx(float(block.get("fps", 0.0)), 23.9)
		and int(block.get("drop_frames", 0)) == 3)
	var hm := StreamHealthMonitor.new()
	var cfg := _make_config(11940)
	var now := Time.get_ticks_msec()
	hm.begin_session(cfg, now)
	var dead := hm.evaluate(now, false, 10.0)
	check("health_dead_process_flagged",
		not bool(dead["healthy"]) and dead["issues"].has("PROCESS_DEAD"))
	hm.update_progress({"frame": 10, "fps": 24.0, "bitrate": "400.0kbits/s",
		"drop_frames": 0, "dup_frames": 0}, now)
	var stalled := hm.evaluate(now + 11000, true, 10.0)
	check("health_stall_flagged", stalled["issues"].has("OUTPUT_STALLED"))
	var snap := hm.snapshot(now, true, 1234)
	check("snapshot_fields_present",
		snap.has("uptime_sec") and snap.has("dropped_frames")
		and snap.has("reconnect_count") and snap.has("last_error")
		and snap.has("cpu_percent") and snap.has("ram_mb"))

# --- Admin + preparation --------------------------------------------------------

func _test_admin_and_prepare() -> void:
	var manager := _new_manager()
	var admin := StreamAdmin.new(manager)
	admin.set_admin_token(ADMIN)
	var cfg := _make_config(11941)
	cfg.log_file_path = _tmp_dir().path_join("stream.log")
	var prep := admin.prepare_stream(_input_spec(), cfg)
	check("admin_prepare_ok", bool(prep["ok"]))
	check("prepare_spawns_nothing", manager.pid == -1
		and manager.state == StreamManager.STATE_PREPARED)
	var bad_spec := _input_spec()
	bad_spec["audio_path"] = _tmp_dir().path_join("missing.wav")
	var m2 := _new_manager()
	var prep2 := m2.prepare(bad_spec, _make_config(11941))
	check("prepare_missing_audio_rejected", not bool(prep2["valid"])
		and prep2["errors"].has("audio_input_missing"))
	# Missing credentials: prepare fails, start is refused, no process.
	var m3 := _new_manager()
	var a3 := StreamAdmin.new(m3)
	a3.set_admin_token(ADMIN)
	var prep3 := a3.prepare_stream(_input_spec(), _make_config(11941, false))
	var start3 := a3.start_stream(ADMIN)
	check("start_without_credentials_refused",
		not bool(prep3["ok"]) and not bool(start3["ok"]) and m3.pid == -1)
	# Authorization: every sensitive action refuses a wrong token.
	var w1 := admin.start_stream("wrong")
	var w2 := admin.stop_stream("wrong")
	var w3 := admin.view_logs("wrong")
	var w4 := admin.set_auto_recovery("wrong", false)
	var w5 := admin.configure_quality("wrong", "720p")
	check("admin_wrong_token_refused",
		not bool(w1["ok"]) and not bool(w2["ok"]) and not bool(w3["ok"])
		and not bool(w4["ok"]) and not bool(w5["ok"]))
	var no_token := StreamAdmin.new(_new_manager()).start_stream(ADMIN)
	check("admin_empty_token_refused", not bool(no_token["ok"]))

# --- Real local RTMP flow ---------------------------------------------------------

func _test_local_stream_flow() -> void:
	var port := 11941
	var listener := _start_listener(port, "flow_out.flv")
	await get_tree().create_timer(0.5).timeout
	var manager := _managers[0] as StreamManager
	var admin := StreamAdmin.new(manager)
	admin.set_admin_token(ADMIN)
	var started := admin.start_stream(ADMIN)
	check("stream_starts", bool(started["ok"]) and manager.pid > 0,
		str(started))
	var pid1 := manager.pid
	var flowed := await _wait_until(
		func() -> bool: return manager.health.frames_sent >= 24, 10.0)
	check("stream_data_flows", flowed,
		"frames=%d" % manager.health.frames_sent)
	var dup := admin.start_stream(ADMIN)
	check("duplicate_start_refused", not bool(dup["ok"])
		and str(dup.get("error", "")) == "already_running"
		and manager.pid == pid1)
	var snap := admin.check_health()
	check("monitoring_snapshot_live",
		float(snap["uptime_sec"]) > 0.0 and int(snap["target_fps"]) == 24
		and snap.has("dropped_frames") and int(snap["reconnect_count"]) == 0
		and float(snap["measured_fps"]) > 0.0,
		"fps=%.1f" % float(snap["measured_fps"]))
	var quality := admin.configure_quality(ADMIN, "720p")
	check("quality_change_refused_while_streaming", not bool(quality["ok"]))
	var stopped := admin.stop_stream(ADMIN)
	await get_tree().create_timer(0.3).timeout
	check("graceful_stop", bool(stopped["ok"])
		and not StreamManager._pid_alive(pid1)
		and manager.state == StreamManager.STATE_STOPPED)
	check("lock_released_on_stop",
		not FileAccess.file_exists(manager._runtime_dir.path_join("stream.lock")))
	_kill(listener)
	await get_tree().create_timer(0.5).timeout
	var info := _ff.probe(_tmp_dir().path_join("flow_out.flv"))
	var codecs: Array = []
	for stream_v in info.get("streams", []):
		codecs.append(str((stream_v as Dictionary).get("codec_name", "")))
	check("listener_recorded_h264_aac", codecs.has("h264") and codecs.has("aac"),
		str(codecs))

# --- Public confirmation safeguard ---------------------------------------------------

func _test_public_confirmation() -> void:
	var port := 11942
	var listener := _start_listener(port, "public_out.flv")
	await get_tree().create_timer(0.5).timeout
	var manager := _new_manager()
	var admin := StreamAdmin.new(manager)
	admin.set_admin_token(ADMIN)
	var cfg := _make_config(port)
	cfg.visibility = "public"
	admin.prepare_stream(_input_spec(), cfg)
	var refused := admin.start_stream(ADMIN)  # no confirmation flag
	check("public_start_requires_confirmation",
		not bool(refused["ok"])
		and str(refused.get("error", "")) == "public_confirmation_required"
		and manager.pid == -1 and manager.state == StreamManager.STATE_PREPARED)
	# With the explicit flag the gate opens — still only against the
	# LOCAL listener; no YouTube endpoint is involved in this test.
	var started := admin.start_stream(ADMIN, true)
	check("public_with_confirmation_starts_locally", bool(started["ok"]))
	var flowed := await _wait_until(
		func() -> bool: return manager.health.frames_sent >= 12, 10.0)
	check("public_local_stream_flows", flowed)
	admin.stop_stream(ADMIN)
	_kill(listener)

# --- Crash detection + bounded recovery -------------------------------------------------

func _test_crash_recovery() -> void:
	var port := 11943
	var listener := _start_listener(port, "crash_out1.flv")
	await get_tree().create_timer(0.5).timeout
	var manager := _new_manager()
	var admin := StreamAdmin.new(manager)
	admin.set_admin_token(ADMIN)
	var cfg := _make_config(port)
	cfg.reconnect_base_delay_sec = 0.5
	cfg.reconnect_max_delay_sec = 1.0
	cfg.max_reconnect_attempts = 3
	admin.prepare_stream(_input_spec(), cfg)
	admin.start_stream(ADMIN)
	var pid1 := manager.pid
	var flowed := await _wait_until(
		func() -> bool: return manager.health.frames_sent >= 12, 10.0)
	check("crash_test_stream_flowing", flowed)
	# Kill the encoder hard, and give the manager a fresh listener
	# to reconnect to (the ffmpeg listener accepts one connection).
	_kill(pid1, "-KILL")
	_kill(listener)
	await get_tree().create_timer(0.3).timeout
	_start_listener(port, "crash_out2.flv")
	var recovered := await _wait_until(
		func() -> bool: return manager.state == StreamManager.STATE_STREAMING \
			and manager.pid > 0 and manager.pid != pid1, 12.0)
	check("crash_detected_and_recovered", recovered,
		"state=%s reconnects=%d" % [manager.state, manager.health.reconnect_count])
	check("reconnect_counted", manager.health.reconnect_count >= 1)
	# Non-vacuous flow proof: the SECOND listener must have recorded
	# a valid H.264 stream from the respawned encoder.
	await get_tree().create_timer(1.5).timeout
	admin.stop_stream(ADMIN)
	for pid_v in _listener_pids:
		_kill(int(pid_v))
	await get_tree().create_timer(0.5).timeout
	var info2 := _ff.probe(_tmp_dir().path_join("crash_out2.flv"))
	var codecs2: Array = []
	for stream_v in info2.get("streams", []):
		codecs2.append(str((stream_v as Dictionary).get("codec_name", "")))
	check("recovered_stream_flows", codecs2.has("h264"), str(codecs2))

# --- Network interruption -------------------------------------------------------------------

func _test_network_interruption() -> void:
	var port := 11944
	var listener := _start_listener(port, "net_out.flv")
	await get_tree().create_timer(0.5).timeout
	var manager := _new_manager()
	var admin := StreamAdmin.new(manager)
	admin.set_admin_token(ADMIN)
	var cfg := _make_config(port)
	cfg.reconnect_base_delay_sec = 0.5
	cfg.reconnect_max_delay_sec = 1.0
	cfg.max_reconnect_attempts = 5
	admin.prepare_stream(_input_spec(), cfg)
	admin.start_stream(ADMIN)
	var flowed := await _wait_until(
		func() -> bool: return manager.health.frames_sent >= 12, 10.0)
	check("net_test_stream_flowing", flowed)
	_kill(listener)  # the remote end vanishes mid-stream
	var noticed := await _wait_until(
		func() -> bool: return manager.health.network_interruptions >= 1 \
			and manager.health.reconnect_count >= 1, 12.0)
	check("network_interruption_detected", noticed,
		"interruptions=%d reconnects=%d state=%s" % [
			manager.health.network_interruptions,
			manager.health.reconnect_count, manager.state])
	admin.stop_stream(ADMIN)

# --- Reconnect limits ----------------------------------------------------------------------------

func _test_reconnect_bounded() -> void:
	var port := 11945  # nothing listens here: every connect is refused
	var manager := _new_manager()
	var admin := StreamAdmin.new(manager)
	admin.set_admin_token(ADMIN)
	var cfg := _make_config(port)
	cfg.reconnect_base_delay_sec = 0.5
	cfg.reconnect_max_delay_sec = 1.0
	cfg.max_reconnect_attempts = 2
	admin.prepare_stream(_input_spec(), cfg)
	var started := admin.start_stream(ADMIN)
	check("dead_target_start_attempted", bool(started["ok"]))
	var gave_up := await _wait_until(
		func() -> bool: return manager.state == StreamManager.STATE_FAILED, 15.0)
	check("reconnects_bounded_then_failed", gave_up,
		"attempts=%d" % int(manager.get_status()["reconnect_attempts"]))
	check("attempts_equal_max",
		int(manager.get_status()["reconnect_attempts"]) == 2)
	var attempts_before := int(manager.get_status()["reconnect_attempts"])
	for i in 5:
		manager.poll()
	await get_tree().create_timer(2.0).timeout
	check("no_retries_after_giveup",
		int(manager.get_status()["reconnect_attempts"]) == attempts_before
		and manager.state == StreamManager.STATE_FAILED)

func _test_recovery_disabled() -> void:
	var port := 11946  # nothing listens here either
	var manager := _new_manager()
	var admin := StreamAdmin.new(manager)
	admin.set_admin_token(ADMIN)
	var cfg := _make_config(port)
	cfg.auto_recovery = false
	admin.prepare_stream(_input_spec(), cfg)
	admin.start_stream(ADMIN)
	var failed := await _wait_until(
		func() -> bool: return manager.state == StreamManager.STATE_FAILED, 10.0)
	check("recovery_disabled_fails_fast", failed
		and int(manager.get_status()["reconnect_attempts"]) == 0)

# --- Redaction across every surface ---------------------------------------------------------------

func _test_redaction_everywhere() -> void:
	var haystack := ""
	for m_v in _managers:
		var m := m_v as StreamManager
		haystack += JSON.stringify(m.get_logs())
		haystack += JSON.stringify(m.get_status())
		haystack += m.config.summary() if m.config != null else ""
	var log_path := _tmp_dir().path_join("stream.log")
	if FileAccess.file_exists(log_path):
		var f := FileAccess.open(log_path, FileAccess.READ)
		haystack += f.get_as_text()
		f.close()
	check("logs_and_status_never_contain_key", not haystack.contains(FAKE_KEY))
	# Sanity: the key really was in play — the process command (the
	# one place it belongs) does carry it, so the check above is not
	# vacuous.
	var probe := _managers[0] as StreamManager
	check("process_args_carry_key_internally",
		" ".join(probe.build_stream_args()).contains(FAKE_KEY))

func _cleanup_processes() -> void:
	for m_v in _managers:
		(m_v as StreamManager).stop_stream()
	for pid_v in _listener_pids:
		_kill(int(pid_v), "-KILL")
