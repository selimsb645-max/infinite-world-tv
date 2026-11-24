class_name FFmpegManager
extends RefCounted
## Phase 06 — the single gateway to the external ffmpeg/ffprobe
## binaries (free, open-source; no paid encoder anywhere). Builds the
## encode and (future) RTMP commands from an EncodingConfig, runs
## them, monitors exit codes and validates finished files with
## ffprobe: codecs, resolution, frame rate, duration and the audio/
## video sync offset. Streaming itself is NOT started in this phase:
## build_rtmp_args() exists for inspection and tests, and
## streaming_allowed() stays false until a later phase enables it.

var ffmpeg_path: String = "ffmpeg"
var ffprobe_path: String = "ffprobe"

var _available_cache: int = -1  # -1 unknown, 0 no, 1 yes

func _init(cfg: EncodingConfig = null) -> void:
	if cfg != null:
		ffmpeg_path = cfg.ffmpeg_path
		ffprobe_path = cfg.ffprobe_path

func is_available() -> bool:
	if _available_cache >= 0:
		return _available_cache == 1
	var out: Array = []
	var code := OS.execute(ffmpeg_path, PackedStringArray(["-version"]), out)
	_available_cache = 1 if code == 0 else 0
	return _available_cache == 1

## Runs a command to completion and reports its exit code and merged
## output. Blocking by design: encodes in this pipeline are bounded
## segment jobs, and the caller (VideoRenderer) measures the wall
## time as the encoding-latency metric.
func run(args: PackedStringArray) -> Dictionary:
	var out: Array = []
	var started := Time.get_ticks_msec()
	var code := OS.execute(ffmpeg_path, args, out, true)
	return {
		"exit_code": code,
		"output": "\n".join(PackedStringArray(out)),
		"seconds": float(Time.get_ticks_msec() - started) / 1000.0,
	}

## Encode args: PNG frame sequence (+ optional mixed WAV) -> MP4.
## The output path should be the segment's .partial.mp4 name; the
## segment manager renames it once validation passes (safe
## finalization). -t pins the duration so A/V stay in sync even if
## the frame count is a little short or long.
func build_encode_args(frames_pattern: String, audio_path: String,
		out_path: String, cfg: EncodingConfig, duration_sec: float) -> PackedStringArray:
	var args := PackedStringArray([
		"-y",
		"-framerate", str(cfg.fps),
		"-i", frames_pattern,
	])
	if audio_path != "":
		args.append_array(PackedStringArray(["-i", audio_path]))
	args.append_array(PackedStringArray([
		"-c:v", "libx264",
		"-preset", cfg.x264_preset,
		"-b:v", "%dk" % cfg.video_bitrate_kbps,
		"-pix_fmt", "yuv420p",
		"-r", str(cfg.fps),
	]))
	if audio_path != "":
		args.append_array(PackedStringArray([
			"-c:a", "aac",
			"-b:a", "%dk" % cfg.audio_bitrate_kbps,
			"-ar", "44100",
		]))
	if duration_sec > 0.0:
		args.append_array(PackedStringArray(["-t", "%.3f" % duration_sec]))
	args.append_array(PackedStringArray(["-movflags", "+faststart", out_path]))
	return args

## RTMP/FLV args for the LATER streaming phase. Built and unit-tested
## here; never executed while cfg.rtmp_enabled is false.
func build_rtmp_args(frames_pattern: String, audio_path: String,
		cfg: EncodingConfig) -> PackedStringArray:
	var args := build_encode_args(frames_pattern, audio_path, "pipe:", cfg, 0.0)
	# Swap the file tail for the FLV/RTMP tail.
	args.remove_at(args.size() - 1)  # out path placeholder
	args.remove_at(args.size() - 1)  # faststart value
	args.remove_at(args.size() - 1)  # -movflags
	args.append_array(PackedStringArray(["-f", "flv", cfg.rtmp_url]))
	return args

func streaming_allowed(cfg: EncodingConfig) -> bool:
	return cfg.rtmp_enabled and cfg.rtmp_url != ""

## ffprobe wrapper: returns the parsed JSON dict, or {} on failure.
func probe(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var out: Array = []
	var code := OS.execute(ffprobe_path, PackedStringArray([
		"-v", "quiet", "-print_format", "json",
		"-show_streams", "-show_format", path]), out)
	if code != 0 or out.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(str(out[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

## Validates a finished segment against the config. av_sync_offset is
## |video duration - audio duration| in seconds (0 when no audio).
func validate(path: String, cfg: EncodingConfig, expect_audio: bool) -> Dictionary:
	var issues: Array[String] = []
	var info := probe(path)
	if info.is_empty():
		return {"valid": false, "issues": ["probe_failed"], "av_sync_offset": -1.0}
	var video: Dictionary = {}
	var audio: Dictionary = {}
	for stream_v in info.get("streams", []):
		var stream: Dictionary = stream_v
		if stream.get("codec_type", "") == "video" and video.is_empty():
			video = stream
		elif stream.get("codec_type", "") == "audio" and audio.is_empty():
			audio = stream
	if video.is_empty():
		issues.append("no_video_stream")
	else:
		if str(video.get("codec_name", "")) != "h264":
			issues.append("video_codec_not_h264")
		if int(video.get("width", 0)) != cfg.width or int(video.get("height", 0)) != cfg.height:
			issues.append("resolution_mismatch")
		var fps := _stream_fps(video)
		if fps > 0.0 and absf(fps - float(cfg.fps)) > 1.5:
			issues.append("fps_mismatch")
	if expect_audio:
		if audio.is_empty():
			issues.append("no_audio_stream")
		elif str(audio.get("codec_name", "")) != "aac":
			issues.append("audio_codec_not_aac")
	var format: Dictionary = info.get("format", {})
	var duration := float(format.get("duration", 0.0))
	if duration <= 0.0:
		issues.append("zero_duration")
	var sync_offset := 0.0
	if not video.is_empty() and not audio.is_empty():
		sync_offset = absf(float(video.get("duration", duration))
			- float(audio.get("duration", duration)))
	return {
		"valid": issues.is_empty(),
		"issues": issues,
		"duration": duration,
		"av_sync_offset": sync_offset,
		"video_fps": _stream_fps(video),
	}

func _stream_fps(stream: Dictionary) -> float:
	var rate := str(stream.get("avg_frame_rate", "0/1"))
	var parts := rate.split("/")
	if parts.size() == 2:
		var den := float(parts[1])
		if den > 0.0:
			return float(parts[0]) / den
	return float(stream.get("r_frame_rate", 0.0))
