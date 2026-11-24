class_name StorageManager
extends RefCounted
## Phase 06 — keeps recording storage bounded, always. The renderer
## calls enforce() after every finalized segment: retention expiry
## first, then the total-size cap, then the segment-count cap,
## deleting oldest-first and never touching the protected (newest /
## in-progress) file. Combined with the encode-to-partial scheme this
## is what guarantees disk usage cannot grow without limit, even if
## the game records forever.

## {bytes, mb, segments, partials} for one output directory.
func usage(dir: String) -> Dictionary:
	var total := 0
	var segments := 0
	var partials := 0
	var d := DirAccess.open(dir)
	if d != null:
		for name in d.get_files():
			var path := dir.path_join(name)
			if name.ends_with(".partial.mp4"):
				partials += 1
				total += _file_size(path)
			elif name.ends_with(".mp4"):
				segments += 1
				total += _file_size(path)
	return {"bytes": total, "mb": float(total) / 1048576.0,
		"segments": segments, "partials": partials}

func headroom_ok(dir: String, cfg: EncodingConfig) -> bool:
	return float(usage(dir)["mb"]) < cfg.max_storage_mb

## Applies retention + caps. Returns {deleted: [paths], freed_bytes}.
func enforce(dir: String, cfg: EncodingConfig,
		segments: VideoSegmentManager, protected_path: String = "") -> Dictionary:
	var deleted: Array = []
	var freed := 0
	var list := segments.list_segments(dir)
	var now := int(Time.get_unix_time_from_system())
	# 1) Retention: expired segments go first.
	if cfg.retention_sec > 0.0:
		var kept: Array = []
		for seg_v in list:
			var seg: Dictionary = seg_v
			if str(seg["path"]) != protected_path \
					and now - int(seg["modified"]) > int(cfg.retention_sec):
				freed += _delete(str(seg["path"]), deleted)
			else:
				kept.append(seg)
		list = kept
	# 2) Size cap, then 3) count cap — oldest first either way.
	var total := 0
	for seg_v in list:
		total += int((seg_v as Dictionary)["size"])
	while list.size() > 0 and (float(total) / 1048576.0 > cfg.max_storage_mb
			or list.size() > cfg.max_segments):
		var oldest: Dictionary = list[0]
		if str(oldest["path"]) == protected_path:
			break
		total -= int(oldest["size"])
		freed += _delete(str(oldest["path"]), deleted)
		list.remove_at(0)
	return {"deleted": deleted, "freed_bytes": freed}

func _delete(path: String, deleted: Array) -> int:
	var size := _file_size(path)
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK:
		deleted.append(path)
		return size
	return 0

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size
