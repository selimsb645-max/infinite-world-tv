extends Node
## Phase 08 — dashboard bridge for the GAME process (additive; the
## game never knows about the dashboard unless this node is present
## AND the IWT_DASHBOARD_DIR environment variable is set).
##
## This node is the root of res://dashboard/GameService.tscn, which
## instances the normal Main scene as a child. It does two things:
##
##   1. Status: every second it writes game_status.json into the
##      runtime dir — real fields read live from GameManager, the
##      AutonomousController, the gameplay RecoveryManager and the
##      Phase 06 VideoRenderer. Nothing is simulated: if a subsystem
##      was never created, the snapshot says so ("present": false).
##
##   2. Commands: it polls game_cmd.json in the same dir. The
##      dashboard backend writes {"id", "action", "params"}; the
##      bridge executes the action against the real game objects
##      and writes game_result_<id>.json with the actual outcome.
##
## The bridge holds no credentials and writes no secrets. File
## writes are atomic (tmp file + rename) so a reader never sees a
## half-written snapshot.

const STATUS_INTERVAL := 1.0
const CMD_INTERVAL := 0.25

var _dir: String = ""
var _game: Node = null
var _status_t := 0.0
var _cmd_t := 0.0

func _ready() -> void:
	_dir = OS.get_environment("IWT_DASHBOARD_DIR").strip_edges()
	if _dir == "":
		set_process(false)
		return
	DirAccess.make_dir_recursive_absolute(_dir)
	_game = get_node_or_null("Main")
	_write_status()

func _process(delta: float) -> void:
	if _game == null:
		_game = get_node_or_null("Main")
		if _game == null:
			return
	_status_t += delta
	_cmd_t += delta
	if _cmd_t >= CMD_INTERVAL:
		_cmd_t = 0.0
		_poll_command()
	if _status_t >= STATUS_INTERVAL:
		_status_t = 0.0
		_write_status()

# --- Status --------------------------------------------------------------

func _write_status() -> void:
	var snap := _snapshot()
	_write_json(_dir.path_join("game_status.json"), snap)

func _snapshot() -> Dictionary:
	var snap := {
		"ts": Time.get_unix_time_from_system(),
		"service_pid": OS.get_process_id(),
		"fps": Engine.get_frames_per_second(),
	}
	if _game == null:
		snap["game_present"] = false
		return snap
	snap["game_present"] = true
	var state_idx := int(_game.get("state"))
	snap["state"] = ["MENU", "PLAYING", "PAUSED"][clampi(state_idx, 0, 2)]
	snap["score"] = int(_game.get("score"))
	snap["mode"] = str(_game.get("mode"))
	snap["endless_active"] = bool(_game.get("endless_active"))
	var env_mgr: Node = _game.get("environment_manager")
	snap["world"] = str(env_mgr.get("current_theme")) if env_mgr != null else ""
	# Current level: generated (endless) or handcrafted.
	var level: Dictionary = {}
	var gen: Dictionary = _game.get("_current_generated")
	if bool(_game.get("endless_active")) and not gen.is_empty():
		level = gen.get("level", {})
		snap["level_seed"] = gen.get("seed", level.get("seed", null))
		snap["difficulty_index"] = gen.get("difficulty_index", null)
	else:
		var lm: Node = _game.get("level_manager")
		if lm != null:
			level = lm.call("current_level")
		snap["level_seed"] = null
		snap["difficulty_index"] = null
	snap["level_name"] = str(level.get("name", ""))
	snap["level_number"] = level.get("level_number", null)
	snap["level_length"] = float(level.get("length", 0.0))
	snap["progress"] = _progress(level)
	# AI controller (Phase 04).
	var ac: Node = _game.get("autonomous_controller")
	if ac != null:
		var ai := {
			"present": true,
			"enabled": bool(ac.get("enabled")),
			"stats": ac.call("stats"),
		}
		var rec: RefCounted = ac.get("recovery")
		if rec != null:
			ai["recovery_events"] = int(rec.get("events"))
			ai["recovery_restarts_this_level"] = int(rec.get("restarts_this_level"))
		snap["ai"] = ai
	else:
		snap["ai"] = {"present": false, "enabled": false}
	# Rendering (Phase 06), only if setup_broadcast() was called.
	var bc: Node = _game.get("broadcast")
	if bc != null:
		var perf: Dictionary = bc.get("perf")
		var br := {
			"present": true,
			"recording": bool(bc.get("recording")),
			"continuous": bool(bc.get("continuous")),
			"segment_index": int(bc.get("segment_index")),
			"perf": perf,
			"recovery_attempts": (bc.get("recovery") as RefCounted).get("attempts")
				if bc.get("recovery") != null else {},
			"recovery_log_tail": _tail(bc.get("recovery_log"), 5),
		}
		snap["broadcast"] = br
	else:
		snap["broadcast"] = {"present": false, "recording": false,
			"continuous": false}
	return snap

func _progress(level: Dictionary) -> float:
	if int(_game.get("state")) != 1:  # PLAYING
		return 0.0
	var length := float(level.get("length", 0.0))
	if length <= 0.0:
		return 0.0
	var ctrl: Node = _game.call("active_controller")
	if ctrl == null:
		return 0.0
	return clampf(-(ctrl as Node3D).global_position.z / length, 0.0, 1.0)

func _tail(arr: Array, n: int) -> Array:
	var out: Array = []
	var start := maxi(0, arr.size() - n)
	for i in range(start, arr.size()):
		out.append(arr[i])
	return out

# --- Commands --------------------------------------------------------------

func _poll_command() -> void:
	var path := _dir.path_join("game_cmd.json")
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
	var params: Dictionary = parsed.get("params", {})
	var result := _execute(action, params)
	result["id"] = id
	result["action"] = action
	_write_json(_dir.path_join("game_result_%s.json" % id), result)
	_write_status()

func _execute(action: String, params: Dictionary) -> Dictionary:
	if _game == null:
		return {"ok": false, "error": "game_not_ready"}
	match action:
		"start_ai":
			var seed := int(params.get("seed", 777))
			_game.call("start_autonomous", seed)
			return {"ok": true, "state": _state_name()}
		"start_game":
			_game.call("start_game", "character", "")
			return {"ok": true, "state": _state_name()}
		"pause_ai":
			var ac: Node = _game.get("autonomous_controller")
			if ac == null:
				return {"ok": false, "error": "ai_not_started"}
			ac.set("enabled", false)
			var inp: Node = ac.get("input")
			if inp != null:
				inp.call("stop_all")
			return {"ok": true, "ai_enabled": false}
		"resume_ai":
			var ac2: Node = _game.get("autonomous_controller")
			if ac2 == null:
				return {"ok": false, "error": "ai_not_started"}
			if int(_game.get("state")) != 1:
				return {"ok": false, "error": "game_not_playing"}
			ac2.set("enabled", true)
			return {"ok": true, "ai_enabled": true}
		"restart_game":
			_game.call("restart_level")
			return {"ok": true, "state": _state_name()}
		"quit_to_menu":
			_game.call("quit_to_menu")
			return {"ok": true, "state": _state_name()}
		"rendering_start":
			var preset := str(params.get("preset", "720p"))
			var cfg := EncodingConfig.preset_1080p(30) if preset == "1080p" \
				else EncodingConfig.preset_720p(30)
			var out_dir := OS.get_environment("IWT_RECORDINGS_DIR").strip_edges()
			if out_dir != "":
				cfg.output_dir = out_dir
			var renderer: Node = _game.call("setup_broadcast", cfg)
			if renderer == null:
				return {"ok": false, "error": "renderer_setup_failed"}
			renderer.call("start_continuous")
			return {"ok": true, "continuous": bool(renderer.get("continuous"))}
		"rendering_stop":
			var bc: Node = _game.get("broadcast")
			if bc == null:
				return {"ok": false, "error": "renderer_not_configured"}
			bc.call("stop_continuous")
			return {"ok": true, "continuous": bool(bc.get("continuous"))}
		"rendering_restart":
			var bc2: Node = _game.get("broadcast")
			if bc2 == null:
				return {"ok": false, "error": "renderer_not_configured"}
			bc2.call("stop_continuous")
			bc2.call("start_continuous")
			return {"ok": true, "continuous": bool(bc2.get("continuous"))}
		"health_check":
			var out := {"ok": true, "fps": Engine.get_frames_per_second(),
				"state": _state_name()}
			var bc3: Node = _game.get("broadcast")
			if bc3 != null:
				var perf: Dictionary = bc3.get("perf")
				if not perf.is_empty():
					out["capture_health"] = (bc3.get("health") as RefCounted).call("evaluate", perf)
			return out
		"quit":
			get_tree().quit()
			return {"ok": true}
	return {"ok": false, "error": "unknown_action"}

func _state_name() -> String:
	return ["MENU", "PLAYING", "PAUSED"][clampi(int(_game.get("state")), 0, 2)]

# --- IO ----------------------------------------------------------------------

func _write_json(path: String, data: Dictionary) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(tmp, path)
