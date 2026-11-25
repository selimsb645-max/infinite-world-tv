extends Node
## Headless reliability suite for INFINITE WORLD TV Phase 09
## (fault recovery & long-run stability hardening) — the GDScript
## half: storage orphan-partial reclamation, windowed recovery
## budgets, bounded stream logging, a 1,000-level deterministic
## generation soak with re-validation and memory measurement, and
## AI perception fault cases. The process-supervision half is
## tests/reliability_test.py.
## Run: godot --headless --path game res://tests/ReliabilityTest.tscn
## Prints PASS/FAIL lines and RELIABILITY_LOGIC_DONE failures=N.

var failures: int = 0

const TMP := "user://reliability_test_tmp"

class NullControllerGame:
	extends RefCounted
	var mode := "character"
	func active_controller():
		return null

func check(test_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
	else:
		failures += 1
		print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func _ready() -> void:
	print("RELIABILITY_LOGIC_START")
	_clean_tmp()
	_test_storage_partials()
	_test_recovery_window()
	_test_stream_log_bounds()
	_test_stream_not_prepared()
	_test_ai_faults()
	_test_generation_soak()
	_clean_tmp()
	print("RELIABILITY_LOGIC_DONE failures=%d" % failures)
	get_tree().quit(mini(failures, 125))

func _tmp_dir() -> String:
	return ProjectSettings.globalize_path(TMP)

func _clean_tmp() -> void:
	_remove_recursive(_tmp_dir())
	DirAccess.make_dir_recursive_absolute(_tmp_dir())

func _remove_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for name in d.get_files():
		d.remove(name)
	for sub in d.get_directories():
		_remove_recursive(path.path_join(sub))
	DirAccess.remove_absolute(path)

func _write_file(path: String, bytes: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var buffer := PackedByteArray()
	buffer.resize(bytes)
	f.store_buffer(buffer)
	f.close()

func _touch_old(path: String, when: String) -> void:
	OS.execute("touch", PackedStringArray(["-d", when, path]))

func _count_lines(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := 0
	while not f.eof_reached():
		if f.get_line() != "":
			n += 1
	f.close()
	return n

# --- StorageManager: orphaned partial reclamation (Phase 09) -----------

func _test_storage_partials() -> void:
	var sm := VideoSegmentManager.new()
	var st := StorageManager.new()
	var dir := _tmp_dir().path_join("partials")
	DirAccess.make_dir_recursive_absolute(dir)
	var old_partial := dir.path_join("iwtv_seg001.partial.mp4")
	var fresh_partial := dir.path_join("iwtv_seg002.partial.mp4")
	var protected_partial := dir.path_join("iwtv_seg003.partial.mp4")
	var segment := dir.path_join("iwtv_seg000.mp4")
	for path in [old_partial, fresh_partial, protected_partial, segment]:
		_write_file(path, 50_000)
	_touch_old(old_partial, "2020-01-01 00:00")
	_touch_old(protected_partial, "2020-01-01 00:00")
	_touch_old(segment, "2020-01-01 00:00")
	var cfg := EncodingConfig.preset_720p(30)
	cfg.max_segments = 99
	cfg.max_storage_mb = 100.0
	cfg.retention_sec = 0.0
	cfg.partial_max_age_sec = 600.0
	var result := st.enforce(dir, cfg, sm, protected_partial)
	check("storage_old_partial_reclaimed",
		not FileAccess.file_exists(old_partial)
		and int(result["partials_deleted"]) == 1,
		"partials_deleted=%s" % str(result.get("partials_deleted")))
	check("storage_fresh_partial_kept",
		FileAccess.file_exists(fresh_partial))
	check("storage_protected_partial_kept",
		FileAccess.file_exists(protected_partial))
	check("storage_finalized_segment_kept_under_caps",
		FileAccess.file_exists(segment))
	# Quota pressure: usage counts partials, so headroom must report
	# the truth — continuous operation is impossible when the caps
	# cannot hold, and the system must be able to SAY so.
	cfg.max_storage_mb = 0.01
	check("storage_headroom_reports_full",
		not st.headroom_ok(dir, cfg))

# --- VideoRecoveryManager: windowed budgets (Phase 09) -----------------

func _test_recovery_window() -> void:
	var rm := VideoRecoveryManager.new()
	rm.budget_window_sec = 60.0
	rm.clock_override_msec = 1_000_000
	check("recovery_first_attempts_allowed",
		rm.plan_action("ENCODE_FAILURE") == "reencode"
		and rm.plan_action("ENCODE_FAILURE") == "reencode"
		and rm.plan_action("ENCODE_FAILURE") == "reencode")
	check("recovery_budget_exhausted_in_window",
		rm.plan_action("ENCODE_FAILURE") == "give_up"
		and rm.exhausted("ENCODE_FAILURE"))
	check("recovery_budgets_are_per_issue",
		rm.plan_action("AUDIO_LOSS") == "reencode_without_audio")
	rm.clock_override_msec += 61_000
	check("recovery_budget_replenishes_after_window",
		rm.can_attempt("ENCODE_FAILURE")
		and rm.plan_action("ENCODE_FAILURE") == "reencode")
	rm.reset()
	check("recovery_reset_still_works",
		rm.actions_taken.is_empty() and rm.can_attempt("AUDIO_LOSS"))

# --- StreamManager: bounded logging (Phase 09) ---------------------------

func _test_stream_log_bounds() -> void:
	var dir := _tmp_dir().path_join("streamlog")
	DirAccess.make_dir_recursive_absolute(dir)
	var log_path := dir.path_join("stream_log.jsonl")
	var cfg := StreamConfig.new()
	cfg.log_file_path = log_path
	var manager := StreamManager.new()
	add_child(manager)
	manager.config = cfg
	for i in 1200:
		manager.log_event("info", "evt_%d" % i, "detail")
	check("stream_log_memory_capped",
		manager.get_logs().size() == StreamManager.LOG_ENTRY_CAP,
		"entries=%d" % manager.get_logs().size())
	check("stream_log_file_complete",
		_count_lines(log_path) == 1200,
		"lines=%d" % _count_lines(log_path))
	# Pre-fill past the size bound: the next event must trigger the
	# one-time rewrite from the capped in-memory window.
	var big := FileAccess.open(log_path, FileAccess.WRITE)
	var chunk := "x".repeat(1024) + "\n"
	for i in 9000:
		big.store_string(chunk)
	big.close()
	manager.log_event("info", "after_bloat", "detail")
	var lines := _count_lines(log_path)
	check("stream_log_file_size_bounded",
		lines > 0 and lines <= StreamManager.LOG_ENTRY_CAP,
		"lines=%d" % lines)
	var f := FileAccess.open(log_path, FileAccess.READ)
	var last := ""
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			last = line
	f.close()
	var parsed = JSON.parse_string(last)
	check("stream_log_last_line_valid_json",
		parsed is Dictionary and str(parsed.get("event", "")) == "after_bloat")
	manager.queue_free()

# --- StreamManager: missing preparation is a clean refusal --------------

func _test_stream_not_prepared() -> void:
	var manager := StreamManager.new()
	add_child(manager)
	var result := manager.start_stream()
	check("stream_start_without_prepare_refused",
		not bool(result.get("ok", true))
		and str(result.get("error", "")) == "not_prepared")
	manager.queue_free()

# --- AI fault cases (Phase 09) ------------------------------------------

func _test_ai_faults() -> void:
	var perception := PerceptionManager.new()
	var stub := NullControllerGame.new()
	var snapshot := perception.sense(stub,
		{"obstacles": [], "gaps": [], "collectibles": [], "segments": []})
	check("ai_perception_unavailable_is_safe",
		snapshot is Dictionary
		and not bool(snapshot.get("available", true))
		and snapshot.has("pos"))
	var recovery := RecoveryManager.new()
	var rec := recovery.update(0.016, {}, true)
	check("ai_recovery_missing_pos_degrades",
		rec is Dictionary and str(rec.get("action", "")) == "none")
	rec = recovery.update(0.016, {"mode": "character"}, true)
	check("ai_recovery_partial_perception_degrades",
		rec is Dictionary and str(rec.get("action", "")) == "none")
	# The stuck ladder itself still functions with real data.
	rec = recovery.update(0.016,
		{"pos": Vector3.ZERO, "mode": "character"}, true)
	check("ai_recovery_normal_path_intact",
		rec is Dictionary and str(rec.get("action", "")) == "none")

# --- Generation soak: 1,000 deterministic levels -------------------------

func _test_generation_soak() -> void:
	var gen := LevelGenerator.new()
	var validator := LevelValidator.new(GenerationConfig.new())
	var mem_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	var fingerprints := {}
	var valid_count := 0
	var fallback_count := 0
	for i in range(1, 1001):
		var result := gen.generate(i, 777000 + i)
		if not bool(result.get("ok", false)):
			continue
		var level: Dictionary = result["level"]
		var difficulty: Dictionary = gen.difficulty_manager.profile_for(i)
		if bool(validator.validate(level, difficulty)["valid"]):
			valid_count += 1
		if bool(result["meta"].get("fallback", false)):
			fallback_count += 1
		fingerprints[str(result["meta"]["fingerprint"])] = true
	var mem_after := Performance.get_monitor(Performance.MEMORY_STATIC)
	var growth_mb := (mem_after - mem_before) / 1048576.0
	print("MEASURED soak: levels=1000 valid=%d fallbacks=%d rejections=%d distinct=%d mem_growth_mb=%.2f"
		% [valid_count, fallback_count, gen.validation_rejections,
			fingerprints.size(), growth_mb])
	check("soak_all_levels_valid", valid_count == 1000,
		"valid=%d/1000" % valid_count)
	check("soak_fallback_template_valid",
		gen.fallback_validation_failures == 0,
		"fallback_validation_failures=%d" % gen.fallback_validation_failures)
	check("soak_levels_distinct", fingerprints.size() == 1000,
		"distinct=%d/1000" % fingerprints.size())
	check("soak_memory_bounded", growth_mb < 50.0,
		"growth=%.2f MB" % growth_mb)
	check("soak_history_bounded",
		gen.history.size() <= GenerationConfig.new().history_size,
		"history=%d" % gen.history.size())
