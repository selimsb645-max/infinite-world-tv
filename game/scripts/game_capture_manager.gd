class_name GameCaptureManager
extends Node
## Phase 06 — real-time viewport frame capture. While recording, it
## grabs the root viewport's rendered image after each
## RenderingServer.frame_post_draw at the configured frame rate,
## scales it to the configured capture resolution and writes a PNG
## frame sequence the FFmpegManager later encodes. Scheduling is
## drop-aware: if the machine cannot keep up, missed slots are
## counted as dropped frames (and reported to the health monitor)
## instead of bursting catch-up grabs. Under Godot's headless dummy
## driver there are no real pixels — grabs come back empty, are
## counted as dropped, and never crash.

var config: EncodingConfig

var capturing: bool = false
var frames_captured: int = 0
var frames_dropped: int = 0
var started_msec: int = 0

var _frames_dir: String = ""
var _frame_index: int = 0
var _next_due_msec: int = 0
var _grab_in_flight: bool = false

func _init(cfg: EncodingConfig = null) -> void:
	config = cfg if cfg != null else EncodingConfig.preset_720p()

func begin(frames_dir: String) -> void:
	_frames_dir = frames_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_dir))
	frames_captured = 0
	frames_dropped = 0
	_frame_index = 0
	started_msec = Time.get_ticks_msec()
	_next_due_msec = started_msec
	capturing = true

func end() -> Dictionary:
	capturing = false
	return stats()

func elapsed_sec() -> float:
	if started_msec == 0:
		return 0.0
	return float(Time.get_ticks_msec() - started_msec) / 1000.0

func capture_fps() -> float:
	var elapsed := elapsed_sec()
	if elapsed <= 0.0:
		return 0.0
	return float(frames_captured) / elapsed

func frames_expected() -> int:
	return int(elapsed_sec() * float(config.fps))

func stats() -> Dictionary:
	return {
		"frames_captured": frames_captured,
		"frames_dropped": frames_dropped,
		"frames_expected": frames_expected(),
		"capture_fps": capture_fps(),
		"elapsed_sec": elapsed_sec(),
	}

func frames_pattern() -> String:
	return ProjectSettings.globalize_path(_frames_dir.path_join("frame_%06d.png"))

func _process(_delta: float) -> void:
	if not capturing or _grab_in_flight:
		return
	var now := Time.get_ticks_msec()
	if now < _next_due_msec:
		return
	var interval := int(1000.0 / float(config.fps))
	# Count whole missed slots as dropped, then reschedule from now.
	var missed := (now - _next_due_msec) / maxi(interval, 1)
	if missed > 0:
		frames_dropped += missed
	_next_due_msec = now + interval
	_grab_in_flight = true
	await RenderingServer.frame_post_draw
	var saved := _save_frame()
	_grab_in_flight = false
	if saved:
		frames_captured += 1
		_frame_index += 1
	else:
		frames_dropped += 1

func _save_frame() -> bool:
	if not capturing and _frame_index == 0:
		return false
	var texture := get_viewport().get_texture()
	if texture == null:
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	var target := config.resolution()
	if image.get_size() != target:
		image.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
	var path := _frames_dir.path_join("frame_%06d.png" % _frame_index)
	return image.save_png(path) == OK
