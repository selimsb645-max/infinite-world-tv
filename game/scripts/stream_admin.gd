class_name StreamAdmin
extends RefCounted
## Phase 07 — the admin control surface (backend only; any future
## dashboard calls this, never ffmpeg or the config directly).
##
## Authorization model: sensitive actions require the admin token
## from the IWT_ADMIN_TOKEN environment variable, compared exactly
## and never logged. Sensitive = start, stop, restart, viewing
## logs, toggling automatic recovery, changing quality. Preparing a
## stream and reading the (secret-free) health snapshot are not
## sensitive: prepare spawns nothing and the snapshot contains no
## credentials by construction.
##
## Starting a PUBLIC broadcast is guarded twice: it needs the admin
## token AND the separate confirm_public flag, which defaults to
## false at every layer. Nothing in this project ever sets it
## automatically.
##
## Every method returns a Dictionary: {"ok": bool, ...} with an
## "error" string on refusal. Errors never contain secret values.

var manager: StreamManager
var _admin_token: String = ""

func _init(stream_manager: StreamManager) -> void:
	manager = stream_manager
	_admin_token = OS.get_environment(StreamConfig.ENV_ADMIN_TOKEN)

## Test/embedding hook: set the expected token without env games.
## The value is stored in memory only, never written anywhere.
func set_admin_token(value: String) -> void:
	_admin_token = value

func _authorized(token: String) -> bool:
	return _admin_token != "" and token == _admin_token

func _refuse() -> Dictionary:
	return {"ok": false, "error": "unauthorized"}

# --- Non-sensitive ------------------------------------------------------

## Validates + stores a stream setup (spawns nothing).
func prepare_stream(input_spec: Dictionary, cfg: StreamConfig) -> Dictionary:
	var verdict := manager.prepare(input_spec, cfg)
	return {"ok": bool(verdict["valid"]), "errors": verdict["errors"]}

## Secret-free health/status snapshot for dashboards.
func check_health() -> Dictionary:
	return manager.get_status()

# --- Sensitive (admin token required) ------------------------------------

func start_stream(token: String, confirm_public: bool = false) -> Dictionary:
	if not _authorized(token):
		return _refuse()
	return manager.start_stream(confirm_public)

func stop_stream(token: String) -> Dictionary:
	if not _authorized(token):
		return _refuse()
	return manager.stop_stream()

func restart_stream(token: String, confirm_public: bool = false) -> Dictionary:
	if not _authorized(token):
		return _refuse()
	return manager.restart_stream(confirm_public)

func view_logs(token: String) -> Dictionary:
	if not _authorized(token):
		return _refuse()
	return {"ok": true, "logs": manager.get_logs()}

func set_auto_recovery(token: String, enabled: bool) -> Dictionary:
	if not _authorized(token):
		return _refuse()
	if manager.config == null:
		return {"ok": false, "error": "not_prepared"}
	manager.config.auto_recovery = enabled
	manager.log_event("info", "auto_recovery_set", "enabled=%s" % enabled)
	return {"ok": true, "auto_recovery": enabled}

## Switches the encoder preset (1080p primary / 720p fallback).
## Refused while streaming — a quality change applies to the next
## start, never silently mid-broadcast.
func configure_quality(token: String, preset_name: String) -> Dictionary:
	if not _authorized(token):
		return _refuse()
	if manager.config == null:
		return {"ok": false, "error": "not_prepared"}
	if manager.is_streaming():
		return {"ok": false, "error": "cannot_change_quality_while_streaming"}
	var fps := manager.config.encoder.fps
	match preset_name:
		"1080p":
			manager.config.encoder = EncodingConfig.preset_1080p(fps)
		"720p":
			manager.config.encoder = EncodingConfig.preset_720p(fps)
		_:
			return {"ok": false, "error": "unknown_preset"}
	manager.log_event("info", "quality_configured", preset_name)
	return {"ok": true, "config": manager.config.summary()}
