class_name EncodingConfig
extends RefCounted
## Phase 06 — every knob of the video production pipeline in one
## validated config object: capture/encode resolution and frame rate,
## bitrates, x264 preset, segmenting, storage caps, audio mix levels
## and the (disabled-by-default) RTMP settings for the later streaming
## phase. No hardware assumptions are hardcoded anywhere else: the
## pipeline reads everything from here, and fallback() produces the
## safe 720p variant used by recovery and by low-power machines.

var width: int = 1920
var height: int = 1080
var fps: int = 30
var video_bitrate_kbps: int = 8000
var audio_bitrate_kbps: int = 160
var x264_preset: String = "veryfast"
var segment_duration_sec: float = 60.0
var output_dir: String = "recordings"
var max_storage_mb: float = 1024.0
var max_segments: int = 48
var retention_sec: float = 0.0  # 0 = keep until a cap forces cleanup
var branding_enabled: bool = true
var channel_name: String = "INFINITE WORLD TV"
var music_db: float = -12.0
var ambience_db: float = -16.0
var sfx_db: float = -3.0
var ffmpeg_path: String = "ffmpeg"
var ffprobe_path: String = "ffprobe"
## Streaming is a LATER phase. These exist so the pipeline can build
## and validate an RTMP command, but rtmp_enabled defaults to false
## and VideoRenderer refuses to stream while it is false.
var rtmp_url: String = ""
var rtmp_enabled: bool = false

static func preset_1080p(target_fps: int = 30) -> EncodingConfig:
	var cfg := EncodingConfig.new()
	cfg.width = 1920
	cfg.height = 1080
	cfg.fps = target_fps
	cfg.video_bitrate_kbps = 8000 if target_fps <= 30 else 12000
	return cfg

static func preset_720p(target_fps: int = 30) -> EncodingConfig:
	var cfg := EncodingConfig.new()
	cfg.width = 1280
	cfg.height = 720
	cfg.fps = target_fps
	cfg.video_bitrate_kbps = 4000 if target_fps <= 30 else 6000
	return cfg

## The safe variant of any config: 720p, fps capped at 30, gentler
## preset. Used by recovery (encoder overload / invalid output) and
## as the documented fallback when 1080p is not sustainable.
func fallback() -> EncodingConfig:
	var cfg := EncodingConfig.new()
	cfg.width = 1280
	cfg.height = 720
	cfg.fps = mini(fps, 30)
	cfg.video_bitrate_kbps = 4000
	cfg.audio_bitrate_kbps = audio_bitrate_kbps
	cfg.x264_preset = "veryfast"
	cfg.segment_duration_sec = segment_duration_sec
	cfg.output_dir = output_dir
	cfg.max_storage_mb = max_storage_mb
	cfg.max_segments = max_segments
	cfg.retention_sec = retention_sec
	cfg.branding_enabled = branding_enabled
	cfg.channel_name = channel_name
	cfg.music_db = music_db
	cfg.ambience_db = ambience_db
	cfg.sfx_db = sfx_db
	cfg.ffmpeg_path = ffmpeg_path
	cfg.ffprobe_path = ffprobe_path
	cfg.rtmp_url = rtmp_url
	cfg.rtmp_enabled = rtmp_enabled
	return cfg

func resolution() -> Vector2i:
	return Vector2i(width, height)

func is_valid() -> bool:
	return width >= 320 and height >= 240 and width % 2 == 0 and height % 2 == 0 \
		and (fps == 24 or fps == 30 or fps == 60) \
		and video_bitrate_kbps >= 200 and audio_bitrate_kbps >= 32 \
		and segment_duration_sec >= 1.0 and max_storage_mb >= 16.0 \
		and max_segments >= 1 and output_dir != ""

func summary() -> String:
	return "%dx%d@%d h264 %dkbps aac %dkbps seg %.0fs" % [
		width, height, fps, video_bitrate_kbps, audio_bitrate_kbps,
		segment_duration_sec]
