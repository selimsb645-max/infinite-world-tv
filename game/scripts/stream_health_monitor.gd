class_name StreamHealthMonitor
extends RefCounted
## Phase 07 — health bookkeeping for one streaming session. The
## StreamManager feeds it ffmpeg's own -progress reports (frame
## count, measured fps, bitrate, dropped/duplicated frames) and
## process events; this class turns them into the snapshot the
## dashboard shows and the issue list recovery acts on.
##
## Issue codes: PROCESS_DEAD, OUTPUT_STALLED, LOW_FPS,
## DROPPING_FRAMES. Pure bookkeeping plus /proc reads — no side
## effects on the stream itself.

const LOW_FPS_RATIO := 0.6
const DROP_RATIO_LIMIT := 0.05
const MIN_EVAL_FRAMES := 240  # ~10 s at 24 fps before fps/drop verdicts

var active: bool = false
var started_unix: int = 0
var target_width: int = 0
var target_height: int = 0
var target_fps: int = 0
var target_video_kbps: int = 0
var target_audio_kbps: int = 0

var frames_sent: int = 0
var measured_fps: float = 0.0
var measured_video_kbps: float = 0.0
var dropped_frames: int = 0
var dup_frames: int = 0
var last_progress_msec: int = 0
var last_health_check_msec: int = 0

var reconnect_count: int = 0
var network_interruptions: int = 0
var last_error: String = ""
var last_error_msec: int = 0
var last_recovery: String = ""
var last_recovery_msec: int = 0

var _cpu_prev: Array = []  # [user, nice, system, idle] jiffies

func begin_session(cfg: StreamConfig, now_msec: int) -> void:
	active = true
	started_unix = int(Time.get_unix_time_from_system())
	if cfg != null and cfg.encoder != null:
		target_width = cfg.encoder.width
		target_height = cfg.encoder.height
		target_fps = cfg.encoder.fps
		target_video_kbps = cfg.encoder.video_bitrate_kbps
		target_audio_kbps = cfg.encoder.audio_bitrate_kbps
	frames_sent = 0
	measured_fps = 0.0
	measured_video_kbps = 0.0
	dropped_frames = 0
	dup_frames = 0
	last_progress_msec = now_msec
	last_health_check_msec = now_msec
	reconnect_count = 0
	network_interruptions = 0
	last_error = ""
	last_recovery = ""
	_cpu_prev = _read_cpu_jiffies()

func end_session() -> void:
	active = false

func note_error(message: String, now_msec: int) -> void:
	last_error = message
	last_error_msec = now_msec

func note_recovery(message: String, now_msec: int) -> void:
	last_recovery = message
	last_recovery_msec = now_msec
	reconnect_count += 1

func note_network_interruption() -> void:
	network_interruptions += 1

## Parses the LAST complete block of an ffmpeg -progress file.
## Blocks are key=value lines terminated by progress=continue|end.
static func parse_progress_file(path: String) -> Dictionary:
	var result: Dictionary = {}
	if path == "" or not FileAccess.file_exists(path):
		return result
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return result
	var text := f.get_as_text()
	f.close()
	var current: Dictionary = {}
	for line in text.split("\n"):
		if not line.contains("="):
			continue
		var key := line.get_slice("=", 0).strip_edges()
		var value := line.get_slice("=", 1).strip_edges()
		current[key] = value
		if key == "progress":
			result = current.duplicate()
			current = {}
	return result

## Feeds one parsed progress block into the running stats.
func update_progress(block: Dictionary, now_msec: int) -> void:
	if block.is_empty():
		return
	last_progress_msec = now_msec
	if block.has("frame"):
		frames_sent = int(block["frame"])
	if block.has("fps"):
		measured_fps = float(block["fps"])
	if block.has("bitrate"):
		measured_video_kbps = _parse_kbits(str(block["bitrate"]))
	if block.has("drop_frames"):
		dropped_frames = int(block["drop_frames"])
	if block.has("dup_frames"):
		dup_frames = int(block["dup_frames"])

func _parse_kbits(text: String) -> float:
	# ffmpeg reports e.g. "2500.5kbits/s" (or "N/A" at startup).
	return float(text.replace("kbits/s", "").strip_edges())

## Health verdict for the current moment. process_running comes
## from the manager (it owns the pid); stall_timeout_sec from the
## config. Returns {"healthy": bool, "issues": Array[String]}.
func evaluate(now_msec: int, process_running: bool,
		stall_timeout_sec: float) -> Dictionary:
	last_health_check_msec = now_msec
	var issues: Array[String] = []
	if not active:
		return {"healthy": true, "issues": issues}
	if not process_running:
		issues.append("PROCESS_DEAD")
	elif now_msec - last_progress_msec > int(stall_timeout_sec * 1000.0) \
			and frames_sent >= 0 and started_unix > 0:
		issues.append("OUTPUT_STALLED")
	if frames_sent >= MIN_EVAL_FRAMES and target_fps > 0 \
			and measured_fps > 0.0 and measured_fps < target_fps * LOW_FPS_RATIO:
		issues.append("LOW_FPS")
	if frames_sent >= MIN_EVAL_FRAMES and dropped_frames > 0:
		var ratio := float(dropped_frames) / float(frames_sent + dropped_frames)
		if ratio > DROP_RATIO_LIMIT:
			issues.append("DROPPING_FRAMES")
	return {"healthy": issues.is_empty(), "issues": issues}

## The dashboard snapshot. Contains no secrets: the ingest URL is
## never stored here at all (the manager adds the redacted form).
func snapshot(now_msec: int, process_running: bool, ffmpeg_pid: int) -> Dictionary:
	var uptime := 0.0
	if active and started_unix > 0:
		uptime = Time.get_unix_time_from_system() - float(started_unix)
	return {
		"active": active,
		"started_unix": started_unix,
		"uptime_sec": uptime,
		"resolution": "%dx%d" % [target_width, target_height],
		"target_fps": target_fps,
		"measured_fps": measured_fps,
		"target_video_kbps": target_video_kbps,
		"measured_video_kbps": measured_video_kbps,
		"target_audio_kbps": target_audio_kbps,
		"frames_sent": frames_sent,
		"dropped_frames": dropped_frames,
		"dup_frames": dup_frames,
		"ffmpeg_running": process_running,
		"ffmpeg_pid": ffmpeg_pid,
		"reconnect_count": reconnect_count,
		"network_interruptions": network_interruptions,
		"cpu_percent": _cpu_percent(),
		"ram_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"last_health_check_msec": last_health_check_msec,
		"last_error": last_error,
		"last_recovery": last_recovery,
	}

func _read_cpu_jiffies() -> Array:
	var f := FileAccess.open("/proc/stat", FileAccess.READ)
	if f == null:
		return []
	var line := f.get_line()
	f.close()
	var parts := line.split(" ", false)
	# parts[0] == "cpu"; then user, nice, system, idle, iowait, ...
	if parts.size() < 5:
		return []
	return [int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])]

## Whole-machine CPU busy % since the previous call (Linux /proc).
## Returns -1.0 when it cannot be measured.
func _cpu_percent() -> float:
	var now := _read_cpu_jiffies()
	if now.is_empty() or _cpu_prev.is_empty():
		if not now.is_empty():
			_cpu_prev = now
		return -1.0
	var busy_prev := int(_cpu_prev[0]) + int(_cpu_prev[1]) + int(_cpu_prev[2])
	var busy_now := int(now[0]) + int(now[1]) + int(now[2])
	var total_prev := busy_prev + int(_cpu_prev[3])
	var total_now := busy_now + int(now[3])
	_cpu_prev = now
	var total_delta := total_now - total_prev
	if total_delta <= 0:
		return -1.0
	return 100.0 * float(busy_now - busy_prev) / float(total_delta)
