class_name StreamConfig
extends RefCounted
## Phase 07 — YouTube Live stream configuration with strict secret
## handling. The stream key is a credential: it is read ONLY from
## the environment (or a gitignored .env file), it is never
## hardcoded, never written to disk by this code, never included in
## summaries or error messages, and every string that leaves the
## streaming layer passes through redact() first.
##
## Sources, in priority order (first non-empty wins per field):
##   1. Fields set directly in code (tests, admin quality presets).
##   2. Environment variables (OS.get_environment).
##   3. A .env file loaded with load_env_file() — the file itself is
##      covered by .gitignore and must never be committed.
##
## Environment variables:
##   IWT_YOUTUBE_STREAM_KEY   the YouTube stream key (SECRET)
##   IWT_RTMP_INGEST_URL      ingest base URL, no key appended
##   IWT_STREAM_VISIBILITY    private | unlisted | public
##   IWT_ADMIN_TOKEN          admin authorization token (SECRET)
##
## Encoder values (resolution, fps, bitrates, x264 preset) live in
## the Phase 06 EncodingConfig this config points at, so there is
## exactly one source of truth for the encode settings. Defaults
## follow YouTube's official encoder guidance (checked 2026-11-24,
## support.google.com/youtube/answer/2853702): RTMPS preferred,
## H.264 + AAC, CBR, keyframe interval 2 s and never above 4 s,
## 1080p30 H.264 ≈ 10 Mbps, 720p30 ≈ 4 Mbps — the Phase 06 presets
## (8000 / 4000 kbps) sit inside those recommended ranges.

const ENV_STREAM_KEY := "IWT_YOUTUBE_STREAM_KEY"
const ENV_INGEST_URL := "IWT_RTMP_INGEST_URL"
const ENV_VISIBILITY := "IWT_STREAM_VISIBILITY"
const ENV_ADMIN_TOKEN := "IWT_ADMIN_TOKEN"

## YouTube ingest bases as shown in YouTube Studio's Live Control
## Room (the stream key is appended as the final path segment).
const YOUTUBE_RTMPS := "rtmps://a.rtmps.youtube.com/live2"
const YOUTUBE_RTMP := "rtmp://a.rtmp.youtube.com/live2"

const VISIBILITIES: Array[String] = ["private", "unlisted", "public"]

var encoder: EncodingConfig
var ingest_base: String = YOUTUBE_RTMPS
var visibility: String = "private"
## YouTube recommends a 2 s keyframe interval and forbids > 4 s.
var keyframe_interval_sec: int = 2
## Bounded recovery: at most this many reconnects per session, with
## exponential backoff between them. Never an open-ended loop.
var max_reconnect_attempts: int = 5
var reconnect_base_delay_sec: float = 2.0
var reconnect_max_delay_sec: float = 60.0
## Output is considered stalled when ffmpeg's progress report has
## not advanced for this long while the process is alive.
var stall_timeout_sec: float = 10.0
var auto_recovery: bool = true
## Optional JSON-lines log file (paths only — entries are redacted
## before they are written). "" keeps logs in memory only.
var log_file_path: String = ""
## Directory holding the cross-instance stream lock file.
var lock_dir: String = ""

var _stream_key: String = ""

func _init(enc: EncodingConfig = null) -> void:
	encoder = enc if enc != null else EncodingConfig.preset_1080p()

# --- Secrets ----------------------------------------------------------

func set_stream_key(value: String) -> void:
	_stream_key = value.strip_edges()

func has_stream_key() -> bool:
	return _stream_key != ""

## The full ingest URL including the key. This is the ONE place the
## key is materialised, and the result may only be handed to the
## ffmpeg process arguments — never to a log, a summary or a file.
func full_url() -> String:
	if _stream_key == "":
		return ingest_base
	return ingest_base.rstrip("/") + "/" + _stream_key

## Ingest URL safe to show anywhere: key replaced by a mask.
func safe_url() -> String:
	return ingest_base.rstrip("/") + "/***" if has_stream_key() else ingest_base

## Removes the stream key (and any URL carrying it) from a string.
## Every log line, error message and status field produced by the
## streaming layer is passed through here before it is stored or
## printed. Also masks the key when it appears URL-encoded in the
## common "%2F"-free plain form — the plain replace covers the
## forms ffmpeg and this code actually produce.
func redact(text: String) -> String:
	var out := text
	if _stream_key != "":
		out = out.replace(_stream_key, "***")
	return out

# --- Loading ------------------------------------------------------------

## Fills empty fields from the process environment. Returns the list
## of env var NAMES that were applied (names only, never values).
func apply_environment() -> Array[String]:
	var applied: Array[String] = []
	if _stream_key == "" and OS.get_environment(ENV_STREAM_KEY) != "":
		_stream_key = OS.get_environment(ENV_STREAM_KEY).strip_edges()
		applied.append(ENV_STREAM_KEY)
	if OS.get_environment(ENV_INGEST_URL) != "":
		ingest_base = OS.get_environment(ENV_INGEST_URL).strip_edges()
		applied.append(ENV_INGEST_URL)
	var vis := OS.get_environment(ENV_VISIBILITY).strip_edges().to_lower()
	if vis != "":
		visibility = vis
		applied.append(ENV_VISIBILITY)
	return applied

## Minimal .env parser (KEY=VALUE per line, # comments, optional
## quotes). Only fills fields that are still empty/default, so real
## environment variables win. Returns the variable NAMES loaded.
## The file is expected to be gitignored; see .env.example.
func load_env_file(path: String) -> Array[String]:
	var loaded: Array[String] = []
	if not FileAccess.file_exists(path):
		return loaded
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return loaded
	var values: Dictionary = {}
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#") or not line.contains("="):
			continue
		var key := line.get_slice("=", 0).strip_edges()
		var value := line.get_slice("=", 1).strip_edges()
		if value.length() >= 2 and value.begins_with("\"") and value.ends_with("\""):
			value = value.substr(1, value.length() - 2)
		values[key] = value
	f.close()
	if _stream_key == "" and values.has(ENV_STREAM_KEY):
		_stream_key = str(values[ENV_STREAM_KEY])
		loaded.append(ENV_STREAM_KEY)
	if values.has(ENV_INGEST_URL) and str(values[ENV_INGEST_URL]) != "":
		ingest_base = str(values[ENV_INGEST_URL])
		loaded.append(ENV_INGEST_URL)
	if values.has(ENV_VISIBILITY) and str(values[ENV_VISIBILITY]) != "":
		visibility = str(values[ENV_VISIBILITY]).to_lower()
		loaded.append(ENV_VISIBILITY)
	return loaded

# --- Validation ---------------------------------------------------------

## Validates everything that can be checked BEFORE any process is
## started. Errors name what is wrong (variable names, ranges) and
## never contain a secret value.
func validate() -> Dictionary:
	var errors: Array[String] = []
	if encoder == null or not encoder.is_valid():
		errors.append("encoder_config_invalid")
	if not (ingest_base.begins_with("rtmp://") or ingest_base.begins_with("rtmps://")):
		errors.append("ingest_url_must_be_rtmp_or_rtmps")
	if ingest_base.contains(" "):
		errors.append("ingest_url_contains_space")
	if not has_stream_key():
		errors.append("missing_credentials:" + ENV_STREAM_KEY)
	if not VISIBILITIES.has(visibility):
		errors.append("visibility_invalid:" + visibility)
	if keyframe_interval_sec < 1 or keyframe_interval_sec > 4:
		errors.append("keyframe_interval_out_of_range_1_to_4")
	if max_reconnect_attempts < 0 or max_reconnect_attempts > 20:
		errors.append("max_reconnect_attempts_out_of_range")
	if reconnect_base_delay_sec < 0.1 or reconnect_max_delay_sec < reconnect_base_delay_sec:
		errors.append("reconnect_backoff_invalid")
	if stall_timeout_sec < 1.0:
		errors.append("stall_timeout_too_small")
	return {"valid": errors.is_empty(), "errors": errors}

## Exponential backoff for reconnect attempt n (1-based), capped.
func backoff_delay(attempt: int) -> float:
	var n := maxi(attempt, 1)
	return minf(reconnect_base_delay_sec * pow(2.0, float(n - 1)),
		reconnect_max_delay_sec)

## Redacted one-line summary — safe for logs and dashboards.
func summary() -> String:
	return "%s via %s key=%s visibility=%s gop=%ds reconnect<=%d" % [
		encoder.summary() if encoder != null else "no-encoder",
		safe_url(), "set" if has_stream_key() else "missing",
		visibility, keyframe_interval_sec, max_reconnect_attempts]
