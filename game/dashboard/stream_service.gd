extends Node
## Phase 08 — persistent streaming service for the dashboard
## (additive; a standalone scene, never part of normal gameplay).
##
## Owns the Phase 07 StreamManager + StreamAdmin pair for as long
## as it runs, so the manager's monitoring/recovery loop (its
## _process) stays alive between dashboard commands — something a
## one-shot CLI invocation cannot provide.
##
## Communication with the dashboard backend is file-based, inside
## the stream runtime dir (IWT_STREAM_RUNTIME_DIR, default the
## Phase 07 user://stream_runtime):
##   stream_status.json    rewritten every 0.5 s from the REAL
##                         StreamAdmin.check_health() snapshot
##   stream_cmd.json       written by the dashboard:
##                         {"id", "action", "confirm_public",
##                          "preset", "enabled"}
##   stream_result_<id>.json  the actual StreamAdmin result
##
## Authorization stays in Phase 07: every sensitive action is
## executed by StreamAdmin with the token taken from this
## process's own IWT_ADMIN_TOKEN environment variable, so the
## token is never written to any file. The dashboard additionally
## authorizes the operator before it writes a command at all.
##
## Credentials come only from the environment (or the .env file
## named by IWT_ENV_FILE). The stream key reaches ffmpeg's
## argument list inside StreamManager and nowhere else; the
## manager's log file (stream_log.jsonl in the runtime dir) is
## redacted by StreamManager itself.

const STATUS_INTERVAL := 0.5
const CMD_INTERVAL := 0.25

var _dir: String = ""
var _config: StreamConfig
var _manager: StreamManager
var _admin: StreamAdmin
var _spec: Dictionary = {}
var _prepare_result: Dictionary = {}
var _status_t := 0.0
var _cmd_t := 0.0

func _ready() -> void:
	_dir = OS.get_environment("IWT_STREAM_RUNTIME_DIR").strip_edges()
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://stream_runtime")
	DirAccess.make_dir_recursive_absolute(_dir)
	var preset := OS.get_environment("IWT_STREAM_PRESET").strip_edges()
	var enc := EncodingConfig.preset_1080p(30) if preset == "1080p" \
		else EncodingConfig.preset_720p(30)
	_config = StreamConfig.new(enc)
	var env_file := OS.get_environment("IWT_ENV_FILE").strip_edges()
	if env_file != "":
		_config.load_env_file(env_file)
	_config.apply_environment()
	_config.lock_dir = _dir
	_config.log_file_path = _dir.path_join("stream_log.jsonl")
	_manager = StreamManager.new()
	_manager.name = "StreamManager"
	add_child(_manager)
	_admin = StreamAdmin.new(_manager)
	_spec = {
		"video_file": OS.get_environment("IWT_STREAM_VIDEO_FILE").strip_edges(),
		"frames_pattern": OS.get_environment("IWT_STREAM_FRAMES_PATTERN").strip_edges(),
		"audio_path": OS.get_environment("IWT_STREAM_AUDIO_PATH").strip_edges(),
	}
	_prepare_result = _admin.prepare_stream(_spec, _config)
	_write_status()

func _process(delta: float) -> void:
	_status_t += delta
	_cmd_t += delta
	if _cmd_t >= CMD_INTERVAL:
		_cmd_t = 0.0
		_poll_command()
	if _status_t >= STATUS_INTERVAL:
		_status_t = 0.0
		_write_status()

# --- Status ---------------------------------------------------------------

func _write_status() -> void:
	var snap := _admin.check_health()
	var out := {
		"ts": Time.get_unix_time_from_system(),
		"service_pid": OS.get_process_id(),
		"manager_state": _manager.state,
		"prepare": _prepare_result,
		"config_summary": _config.summary(),
		"visibility": _config.visibility,
		"has_stream_key": _config.has_stream_key(),
		"auto_recovery": _config.auto_recovery,
		"snapshot": snap,
	}
	_write_json(_dir.path_join("stream_status.json"), out)

# --- Commands ---------------------------------------------------------------

func _poll_command() -> void:
	var path := _dir.path_join("stream_cmd.json")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	DirAccess.remove_absolute(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var id := str(parsed.get("id", ""))
	var action := str(parsed.get("action", ""))
	var token := OS.get_environment(StreamConfig.ENV_ADMIN_TOKEN)
	var result: Dictionary
	match action:
		"prepare":
			_prepare_result = _admin.prepare_stream(_spec, _config)
			result = _prepare_result
		"start":
			result = _admin.start_stream(token, bool(parsed.get("confirm_public", false)))
		"stop":
			result = _admin.stop_stream(token)
		"restart":
			result = _admin.restart_stream(token, bool(parsed.get("confirm_public", false)))
		"health":
			result = {"ok": true, "status": _admin.check_health()}
		"set_auto_recovery":
			result = _admin.set_auto_recovery(token, bool(parsed.get("enabled", true)))
		"configure_quality":
			result = _admin.configure_quality(token, str(parsed.get("preset", "")))
		"quit":
			_admin.stop_stream(token)
			result = {"ok": true}
			_write_json(_dir.path_join("stream_result_%s.json" % id),
				{"id": id, "action": action, "result": result})
			_write_status()
			get_tree().quit()
			return
		_:
			result = {"ok": false, "error": "unknown_action"}
	_write_json(_dir.path_join("stream_result_%s.json" % id),
		{"id": id, "action": action, "result": result})
	_write_status()

# --- IO -----------------------------------------------------------------------

func _write_json(path: String, data: Dictionary) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(tmp, path)
