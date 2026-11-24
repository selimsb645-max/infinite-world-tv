class_name VideoSegmentManager
extends RefCounted
## Phase 06 — recording segment bookkeeping. Segments are encoded to
## a `.partial.mp4` name first and only renamed to their final
## timestamped name after ffprobe validation passes, so a crash or a
## bad encode never leaves a corrupt file that looks finished.
## Interrupted `.partial.mp4` files found on startup are recovered:
## valid ones are promoted, invalid ones discarded — each action is
## reported, nothing is silently kept or deleted.

const FINAL_SUFFIX := ".mp4"
const PARTIAL_SUFFIX := ".partial.mp4"

func segment_basename(segment_index: int, when: Dictionary = {}) -> String:
	var dt := when if not when.is_empty() else Time.get_datetime_dict_from_system()
	return "iwtv_%04d%02d%02d_%02d%02d%02d_seg%03d" % [
		int(dt["year"]), int(dt["month"]), int(dt["day"]),
		int(dt["hour"]), int(dt["minute"]), int(dt["second"]), segment_index]

func final_path(dir: String, segment_index: int) -> String:
	return dir.path_join(segment_basename(segment_index) + FINAL_SUFFIX)

func partial_path(final: String) -> String:
	if final.ends_with(FINAL_SUFFIX):
		return final.left(final.length() - FINAL_SUFFIX.length()) + PARTIAL_SUFFIX
	return final + PARTIAL_SUFFIX

## Promotes a validated partial to its final name. Refuses empty or
## missing files — those stay partial for recovery to judge.
func finalize_segment(partial: String) -> String:
	if not FileAccess.file_exists(partial):
		return ""
	var file := FileAccess.open(partial, FileAccess.READ)
	if file == null or file.get_length() <= 0:
		return ""
	file.close()
	var final := partial.left(partial.length() - PARTIAL_SUFFIX.length()) + FINAL_SUFFIX \
		if partial.ends_with(PARTIAL_SUFFIX) else partial
	if DirAccess.rename_absolute(
			ProjectSettings.globalize_path(partial),
			ProjectSettings.globalize_path(final)) != OK:
		return ""
	return final

## Finalized segments only, oldest first: {path, size, modified}.
func list_segments(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		if name.ends_with(FINAL_SUFFIX) and not name.ends_with(PARTIAL_SUFFIX):
			var path := dir.path_join(name)
			out.append({
				"path": path,
				"size": _file_size(path),
				"modified": FileAccess.get_modified_time(path),
			})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["modified"]) < int(b["modified"]))
	return out

func find_interrupted(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		if name.ends_with(PARTIAL_SUFFIX):
			out.append(dir.path_join(name))
	return out

## Judges every interrupted partial with ffprobe: valid -> promoted
## to its final name ("recovered"), invalid -> deleted
## ("discarded"). Returns the list of {path, action} taken.
func recover_interrupted(dir: String, ffmpeg: FFmpegManager,
		cfg: EncodingConfig) -> Array:
	var actions: Array = []
	for partial in find_interrupted(dir):
		var verdict := ffmpeg.validate(partial, cfg, false)
		if bool(verdict["valid"]):
			var final := finalize_segment(partial)
			actions.append({"path": partial, "action":
				"recovered" if final != "" else "recover_failed"})
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(partial))
			actions.append({"path": partial, "action": "discarded"})
	return actions

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size
