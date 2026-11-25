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
	# 1b) Phase 09 — orphaned partials. Interrupted encodes leave
	# .partial.mp4 files that list_segments() never returns, so the
	# caps below cannot reclaim them, yet usage() counts them: in
	# one long session with repeated encode failures they would
	# grow without bound. Delete only partials older than
	# cfg.partial_max_age_sec — an encode actually in progress is
	# far younger than that, and the caller protects the live one
	# explicitly. (Startup recovery in VideoSegmentManager still
	# judges fresh partials: promote-or-discard.)
	var partials_deleted := 0
	if cfg.partial_max_age_sec > 0.0:
		for partial in segments.find_interrupted(dir):
			if partial == protected_path:
				continue
			if now - FileAccess.get_modified_time(partial) \
					> int(cfg.partial_max_age_sec):
				var before := deleted.size()
				freed += _delete(partial, deleted)
				partials_deleted += deleted.size() - before
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
	return {"deleted": deleted, "freed_bytes": freed,
		"partials_deleted": partials_deleted}

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
