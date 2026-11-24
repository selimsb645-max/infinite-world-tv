class_name AudioMixer
extends RefCounted
## Phase 06 — builds and renders the audio track for a recorded
## segment from Phase 05's original WAV library (music loop, the
## current world's ambience loop, and timestamped one-shot SFX
## events). Levels are configurable per layer (EncodingConfig
## music_db / ambience_db / sfx_db). The render runs through ffmpeg:
## every layer is resampled to 44.1 kHz stereo, trimmed/padded to the
## exact segment duration (that is what keeps A/V in sync), mixed
## with normalize=0, then dynaudnorm + a hard limiter prevent
## clipping. Missing clips never fail the mix: they are skipped and
## reported in the plan, and a plan with no layers at all renders as
## digital silence so the MP4 still carries a valid AAC track.

var config: EncodingConfig
var _library: AudioLibrary

func _init(cfg: EncodingConfig) -> void:
	config = cfg
	_library = AudioLibrary.new()

## events: Array of {clip: String, at: float (seconds), gain_db: float (optional)}
## Returns {duration, tracks, skipped, silent}.
func plan_mix(duration_sec: float, world: String, events: Array = []) -> Dictionary:
	var tracks: Array = []
	var skipped: Array[String] = []
	_add_loop_track(tracks, skipped, "music", config.music_db)
	_add_loop_track(tracks, skipped, AudioLibrary.ambience_for_world(world),
		config.ambience_db)
	for event_v in events:
		var event: Dictionary = event_v
		var clip := str(event.get("clip", ""))
		var path := _clip_path(clip)
		if path == "":
			skipped.append(clip)
			continue
		tracks.append({
			"clip": clip, "path": path, "loop": false,
			"at": clampf(float(event.get("at", 0.0)), 0.0, duration_sec),
			"gain_db": float(event.get("gain_db", config.sfx_db)),
		})
	return {
		"duration": duration_sec,
		"tracks": tracks,
		"skipped": skipped,
		"silent": tracks.is_empty(),
	}

func render_mix(plan: Dictionary, out_path: String, ffmpeg: FFmpegManager) -> Dictionary:
	var duration := float(plan["duration"])
	if bool(plan["silent"]):
		var silent := ffmpeg.run(PackedStringArray([
			"-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
			"-t", "%.3f" % duration, out_path]))
		return {"ok": int(silent["exit_code"]) == 0,
			"exit_code": int(silent["exit_code"]), "silent": true}
	var tracks: Array = plan["tracks"]
	var args := PackedStringArray(["-y"])
	for track_v in tracks:
		var track: Dictionary = track_v
		if bool(track["loop"]):
			args.append_array(PackedStringArray(["-stream_loop", "-1"]))
		args.append_array(PackedStringArray(["-i", str(track["path"])]))
	var filters: Array[String] = []
	for i in tracks.size():
		var track: Dictionary = tracks[i]
		var chain := "[%d:a]aformat=sample_rates=44100:channel_layouts=stereo" % i
		if bool(track["loop"]):
			chain += ",atrim=0:%.3f,asetpts=PTS-STARTPTS" % duration
		else:
			chain += ",adelay=delays=%d:all=1,apad,atrim=0:%.3f" % [
				int(float(track["at"]) * 1000.0), duration]
		chain += ",volume=%.1fdB[t%d]" % [float(track["gain_db"]), i]
		filters.append(chain)
	var mix_inputs := ""
	for i in tracks.size():
		mix_inputs += "[t%d]" % i
	filters.append("%samix=inputs=%d:duration=first:normalize=0[mixed]" % [
		mix_inputs, tracks.size()])
	filters.append("[mixed]dynaudnorm=f=200:g=15,alimiter=limit=0.95[aout]")
	args.append_array(PackedStringArray([
		"-filter_complex", ";".join(filters),
		"-map", "[aout]",
		"-t", "%.3f" % duration,
		"-ar", "44100", "-ac", "2",
		out_path]))
	var result := ffmpeg.run(args)
	return {"ok": int(result["exit_code"]) == 0,
		"exit_code": int(result["exit_code"]), "silent": false,
		"seconds": float(result["seconds"])}

func _add_loop_track(tracks: Array, skipped: Array[String],
		clip: String, gain_db: float) -> void:
	var path := _clip_path(clip)
	if path == "":
		skipped.append(clip)
		return
	tracks.append({"clip": clip, "path": path, "loop": true,
		"at": 0.0, "gain_db": gain_db})

func _clip_path(clip: String) -> String:
	if clip == "" or not AudioLibrary.CLIPS.has(clip):
		return ""
	if _library.stream(clip) == null:
		return ""
	var file := str((AudioLibrary.CLIPS[clip] as Dictionary)["file"])
	return ProjectSettings.globalize_path(AudioLibrary.AUDIO_DIR + file)
