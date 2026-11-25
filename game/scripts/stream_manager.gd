class_name StreamManager
extends Node
## Phase 07 — the automated streaming engine. Owns exactly one
## ffmpeg streaming process fed from the Phase 06 pipeline output
## (a PNG frame sequence at the encoder resolution — exactly what
## GameCaptureManager writes — plus a mixed WAV from AudioMixer,
## or a rendered file in file mode), and pushes FLV over RTMP(S)
## to the configured ingest.
##
## Safety properties, all enforced here:
##   * Preparation is separate from broadcasting: prepare() only
##     validates and stores; start_stream() is the only spawn path.
##   * A public broadcast needs an explicit confirmation flag in
##     addition to a valid config; the default visibility is
##     private and the flag defaults to off.
##   * Duplicate processes are impossible: start refuses while a
##     stream is running, and a lock file (pid-checked) refuses a
##     second manager instance pointing at the same runtime dir.
##   * Recovery is bounded: unexpected exits and output stalls are
##     retried at most StreamConfig.max_reconnect_attempts times
##     with exponential backoff, then the state is FAILED and
##     nothing restarts until an operator acts.
##   * The stream key appears only in the spawned process's
##     argument list (in memory). Every log entry, status field and
##     error string is redacted through StreamConfig.redact().
##
## Process monitoring uses ffmpeg's own -progress report file
## (frame/fps/bitrate/drop counters) plus `ps` liveness — a child
## that has exited but not been reaped is a zombie and must count
## as dead, which kill -0 alone cannot tell.

const STATE_IDLE := "idle"
const STATE_PREPARED := "prepared"
const STATE_STREAMING := "streaming"
const STATE_RECOVERING := "recovering"
const STATE_STOPPED := "stopped"
const STATE_FAILED := "failed"

var config: StreamConfig
var health: StreamHealthMonitor

var state: String = STATE_IDLE
var pid: int = -1

var _input_spec: Dictionary = {}
var _log_entries: Array = []
var _reconnect_attempts: int = 0
var _next_retry_msec: int = 0
var _stop_requested: bool = false
var _progress_path: String = ""
var _runtime_dir: String = ""

func _init() -> void:
	health = StreamHealthMonitor.new()

# --- Preparation (never spawns anything) -------------------------------

## Validates and stores the stream setup. Returns the validation
## dictionary {"valid", "errors"}; on success the state becomes
## PREPARED and start_stream() may be called. Spawns nothing.
func prepare(input_spec: Dictionary, cfg: StreamConfig) -> Dictionary:
	config = cfg
	_input_spec = input_spec.duplicate()
	_runtime_dir = cfg.lock_dir if cfg.lock_dir != "" \
		else ProjectSettings.globalize_path("user://stream_runtime")
	DirAccess.make_dir_recursive_absolute(_runtime_dir)
	_progress_path = _runtime_dir.path_join("stream_progress.txt")
	var errors: Array = []
	var verdict := cfg.validate()
	errors.append_array(verdict["errors"])
	var audio_path := str(input_spec.get("audio_path", ""))
	if audio_path != "" and not FileAccess.file_exists(audio_path):
		errors.append("audio_input_missing")
	if str(input_spec.get("frames_pattern", "")) == "" \
			and str(input_spec.get("video_file", "")) == "":
		errors.append("no_video_input")
	var video_file := str(input_spec.get("video_file", ""))
	if video_file != "" and not FileAccess.file_exists(video_file):
		errors.append("video_input_missing")
	if errors.is_empty():
		state = STATE_PREPARED
		log_event("info", "stream_prepared", cfg.summary())
	else:
		state = STATE_IDLE
		log_event("error", "stream_prepare_failed", ",".join(errors))
	return {"valid": errors.is_empty(), "errors": errors}

# --- Lifecycle ------------------------------------------------------------

## The only spawn path. Refusals (returned, never thrown):
## not_prepared, config_invalid (+errors), missing credentials
## (inside config_invalid errors), public_confirmation_required,
## already_running, already_running_lock.
func start_stream(confirm_public: bool = false) -> Dictionary:
	if config == null or _input_spec.is_empty() or state == STATE_IDLE:
		return {"ok": false, "error": "not_prepared"}
	if state == STATE_STREAMING or state == STATE_RECOVERING:
		return {"ok": false, "error": "already_running"}
	var verdict := config.validate()
	if not bool(verdict["valid"]):
		return {"ok": false, "error": "config_invalid", "errors": verdict["errors"]}
	if config.visibility == "public" and not confirm_public:
		log_event("warn", "public_start_refused", "confirmation flag not set")
		return {"ok": false, "error": "public_confirmation_required"}
	var lock_pid := _lock_holder_pid()
	if lock_pid > 0 and lock_pid != pid and _pid_alive(lock_pid):
		return {"ok": false, "error": "already_running_lock"}
	_reconnect_attempts = 0
	_stop_requested = false
	health.begin_session(config, Time.get_ticks_msec())
	_spawn()
	return {"ok": true, "pid": pid}

## Graceful shutdown: SIGTERM, a bounded wait, SIGKILL as the last
## resort. Also cancels a pending reconnect.
func stop_stream() -> Dictionary:
	_stop_requested = true
	if pid > 0 and _pid_alive(pid):
		OS.execute("kill", PackedStringArray(["-TERM", str(pid)]))
		var waited := 0
		while _pid_alive(pid) and waited < 2500:
			OS.delay_msec(100)
			waited += 100
		if _pid_alive(pid):
			OS.execute("kill", PackedStringArray(["-KILL", str(pid)]))
	pid = -1
	_release_lock()
	if state != STATE_FAILED:
		state = STATE_STOPPED
	health.end_session()
	log_event("info", "stream_stopped", "operator stop")
	return {"ok": true}

func restart_stream(confirm_public: bool = false) -> Dictionary:
	stop_stream()
	state = STATE_PREPARED  # configuration retained; start re-validates
	return start_stream(confirm_public)

func is_streaming() -> bool:
	return state == STATE_STREAMING or state == STATE_RECOVERING

# --- Monitoring / recovery -------------------------------------------------

func _process(_delta: float) -> void:
	if state == STATE_STREAMING or state == STATE_RECOVERING:
		poll()

## One monitoring tick. Public so tests (and an external watchdog)
## can drive it deterministically instead of waiting on frames.
func poll() -> void:
	var now := Time.get_ticks_msec()
	if state == STATE_STREAMING:
		var block := StreamHealthMonitor.parse_progress_file(_progress_path)
		if not block.is_empty():
			health.update_progress(block, now)
		var alive := _pid_alive(pid)
		var verdict := health.evaluate(now, alive, config.stall_timeout_sec)
		if not alive:
			_on_unexpected_exit("ffmpeg_process_exited")
		elif verdict["issues"].has("OUTPUT_STALLED"):
			health.note_network_interruption()
			health.note_error("output_stalled", now)
			log_event("warn", "output_stalled",
				"no progress for %.0fs; restarting encoder" % config.stall_timeout_sec)
			OS.execute("kill", PackedStringArray(["-KILL", str(pid)]))
			_on_unexpected_exit("output_stalled")
	elif state == STATE_RECOVERING:
		if now >= _next_retry_msec:
			log_event("info", "reconnect_attempt",
				"attempt %d of %d" % [_reconnect_attempts, config.max_reconnect_attempts])
			_spawn()

func _on_unexpected_exit(reason: String) -> void:
	var now := Time.get_ticks_msec()
	# A stream that was flowing and stops unrequested is, from the
	# audience's side, an interruption of the broadcast.
	if health.frames_sent > 0:
		health.note_network_interruption()
	health.note_error(reason, now)
	log_event("error", "stream_interrupted", reason)
	_release_lock()
	pid = -1
	if config.auto_recovery and _reconnect_attempts < config.max_reconnect_attempts:
		_reconnect_attempts += 1
		var delay := config.backoff_delay(_reconnect_attempts)
		_next_retry_msec = now + int(delay * 1000.0)
		state = STATE_RECOVERING
		health.note_recovery("reconnect %d scheduled in %.1fs after %s"
			% [_reconnect_attempts, delay, reason], now)
		log_event("warn", "reconnect_scheduled",
			"attempt %d of %d in %.1fs" % [_reconnect_attempts,
				config.max_reconnect_attempts, delay])
	else:
		state = STATE_FAILED
		health.end_session()
		log_event("error", "stream_failed",
			"recovery budget exhausted or disabled after %s" % reason)

func _spawn() -> void:
	var args := build_stream_args()
	if FileAccess.file_exists(_progress_path):
		DirAccess.remove_absolute(_progress_path)
	pid = OS.create_process(config.encoder.ffmpeg_path, args)
	if pid <= 0:
		pid = -1
		_on_unexpected_exit("spawn_failed")
		return
	_write_lock()
	state = STATE_STREAMING
	# Give the encoder a fresh stall window to connect and report.
	health.last_progress_msec = Time.get_ticks_msec()
	log_event("info", "stream_started", "pid=%d %s" % [pid, config.summary()])

# --- Command building ---------------------------------------------------------

## Builds the ffmpeg argument list for the configured stream. The
## returned array contains the full ingest URL INCLUDING the key —
## it is process input only and must never be logged or stored.
## Settings follow YouTube's encoder guidance: H.264 CBR (bitrate
## == maxrate), GOP = fps × keyframe interval (2 s default, ≤ 4 s),
## AAC 44.1 kHz, FLV over RTMP(S).
func build_stream_args() -> PackedStringArray:
	var enc := config.encoder
	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-nostats",
		"-progress", _progress_path, "-stats_period", "0.5",
	])
	var frames_pattern := str(_input_spec.get("frames_pattern", ""))
	var video_file := str(_input_spec.get("video_file", ""))
	if frames_pattern != "":
		args.append_array(PackedStringArray([
			"-re", "-framerate", str(enc.fps), "-i", frames_pattern]))
	elif video_file != "":
		args.append_array(PackedStringArray([
			"-stream_loop", "-1", "-re", "-i", video_file]))
	var audio_path := str(_input_spec.get("audio_path", ""))
	if audio_path != "":
		args.append_array(PackedStringArray([
			"-stream_loop", "-1", "-i", audio_path]))
	else:
		# No audio source: emit a valid silent AAC track rather than
		# failing the stream (Phase 06 does the same for segments).
		args.append_array(PackedStringArray([
			"-f", "lavfi", "-i",
			"anullsrc=channel_layout=stereo:sample_rate=44100"]))
	var gop := enc.fps * config.keyframe_interval_sec
	args.append_array(PackedStringArray([
		"-c:v", "libx264",
		"-preset", enc.x264_preset,
		"-b:v", "%dk" % enc.video_bitrate_kbps,
		"-maxrate", "%dk" % enc.video_bitrate_kbps,
		"-bufsize", "%dk" % (2 * enc.video_bitrate_kbps),
		"-pix_fmt", "yuv420p",
		"-r", str(enc.fps),
		"-g", str(gop),
		"-keyint_min", str(gop),
		"-sc_threshold", "0",
		"-c:a", "aac",
		"-b:a", "%dk" % enc.audio_bitrate_kbps,
		"-ar", "44100",
		"-f", "flv", config.full_url(),
	]))
	return args

# --- Status / logs -----------------------------------------------------------

func get_status() -> Dictionary:
	var status := health.snapshot(Time.get_ticks_msec(),
		pid > 0 and _pid_alive(pid), pid)
	status["state"] = state
	status["reconnect_attempts"] = _reconnect_attempts
	if config != null:
		status["config"] = config.summary()
	return status

func get_logs() -> Array:
	return _log_entries.duplicate()

## Appends one structured entry. The detail string is redacted
## through the config before it is stored anywhere — this is the
## single choke point that keeps the stream key out of the logs.
func log_event(level: String, event: String, detail: String = "") -> void:
	var safe_detail := config.redact(detail) if config != null else detail
	var entry := {
		"ts": Time.get_datetime_string_from_unix_time(
			int(Time.get_unix_time_from_system())),
		"level": level,
		"event": event,
		"detail": safe_detail,
	}
	_log_entries.append(entry)
	_flush_log_file()

func _flush_log_file() -> void:
	if config == null or config.log_file_path == "":
		return
	var f := FileAccess.open(config.log_file_path, FileAccess.WRITE)
	if f == null:
		return
	for entry_v in _log_entries:
		f.store_line(JSON.stringify(entry_v))
	f.close()

# --- Process / lock helpers ----------------------------------------------------

## Linux liveness. A child that exited but was not reaped is a
## zombie: it still answers kill -0 and its /proc entries linger,
## so neither is authoritative. `ps -o stat=` tells the truth:
## no output = no such process, leading Z/X = zombie/dead.
static func _pid_alive(a_pid: int) -> bool:
	if a_pid <= 0:
		return false
	var out: Array = []
	var code := OS.execute("ps", PackedStringArray(
		["-o", "stat=", "-p", str(a_pid)]), out)
	if code == 127:  # ps itself unavailable: last-resort signal probe
		return OS.execute("kill", PackedStringArray(["-0", str(a_pid)])) == 0
	if code != 0 or out.is_empty():
		return false
	var stat := str(out[0]).strip_edges()
	if stat == "":
		return false
	var first := stat.substr(0, 1)
	return first != "Z" and first != "X"

func _lock_path() -> String:
	return _runtime_dir.path_join("stream.lock")

func _write_lock() -> void:
	var f := FileAccess.open(_lock_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(str(pid))
		f.close()

func _release_lock() -> void:
	if _runtime_dir != "" and FileAccess.file_exists(_lock_path()):
		DirAccess.remove_absolute(_lock_path())

func _lock_holder_pid() -> int:
	if _runtime_dir == "" or not FileAccess.file_exists(_lock_path()):
		return -1
	var f := FileAccess.open(_lock_path(), FileAccess.READ)
	if f == null:
		return -1
	var text := f.get_as_text().strip_edges()
	f.close()
	return int(text) if text.is_valid_int() else -1
