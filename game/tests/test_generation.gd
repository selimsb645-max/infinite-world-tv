extends SceneTree
## Phase 03 test suite - procedural generation.
##
## Everything here is data-level except the memory test, which needs real nodes. Run with:
##   godot --headless --path . --script res://tests/test_generation.gd
##
## The suite reports what it actually executed. Nothing is estimated.

var _checks := 0
var _fails := 0
var _t0 := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  PASS  %s%s" % [name, ("  [" + detail + "]") if detail != "" else ""])
	else:
		_fails += 1
		print("  FAIL  %s%s" % [name, ("  [" + detail + "]") if detail != "" else ""])

## Validator stub that refuses everything, used to prove bounded retry + fallback.
class AlwaysInvalid extends LevelValidator:
	func validate(_spec: Dictionary) -> Array:
		return ["forced_invalid"]

func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	print("=== PHASE 03 GENERATION TESTS ===")

	_test_seed_reproducibility()
	_test_large_scale()
	_test_world_diversity()
	_test_duplicates_and_similarity()
	_test_route_validation()
	_test_difficulty_progression()
	_test_invalid_rejection()
	_test_bounded_retry_and_fallback()
	await _test_memory_cleanup()
	_test_history_bounds()

	var secs := float(Time.get_ticks_msec() - _t0) / 1000.0
	print("\nRESULT: %d/%d checks passed (%.2fs)" % [_checks - _fails, _checks, secs])
	if _fails == 0:
		print("ALL PASS")
	quit(0 if _fails == 0 else 1)

# ---------------------------------------------------------------- seeds
func _test_seed_reproducibility() -> void:
	print("\n-- seed reproducibility")
	var a := LevelGenerator.new()
	var b := LevelGenerator.new()
	var l1: Dictionary = a.generate(7, 4242)
	var l2: Dictionary = b.generate(7, 4242)
	_check("same seed gives same fingerprint", l1["fingerprint"] == l2["fingerprint"],
		"%s vs %s" % [l1["fingerprint"], l2["fingerprint"]])
	_check("same seed gives same obstacle count",
		l1["obstacles"].size() == l2["obstacles"].size(),
		"%d" % l1["obstacles"].size())
	var c := LevelGenerator.new()
	var l3: Dictionary = c.generate(7, 9999)
	_check("different seed gives different level", l1["fingerprint"] != l3["fingerprint"])

# ---------------------------------------------------------------- scale
func _test_large_scale() -> void:
	print("\n-- 1000 generated levels")
	var gen := LevelGenerator.new()
	var t := Time.get_ticks_msec()
	var valid := 0
	var both_modes := 0
	var fingerprints := {}
	var total_obstacles := 0
	var fallbacks := 0
	var rejections := 0
	for i in 1000:
		var lvl: Dictionary = gen.generate(i)
		if gen.fallback_used:
			fallbacks += 1
		rejections += gen.last_rejections.size()
		var problems := LevelValidator.new().validate(lvl)
		if problems.is_empty():
			valid += 1
		if fingerprints.has(lvl["fingerprint"]):
			fingerprints[lvl["fingerprint"]] += 1
		else:
			fingerprints[lvl["fingerprint"]] = 1
		var has_v := false
		var has_c := false
		for seg in lvl["segments"]:
			if seg["mode"] == "vehicle":
				has_v = true
			else:
				has_c = true
		if has_v and has_c:
			both_modes += 1
		total_obstacles += lvl["obstacles"].size()
	var ms := Time.get_ticks_msec() - t
	_check("1000 levels generated", true, "%d ms, %.1f levels/s" % [ms, 1000.0 / (float(ms) / 1000.0)])
	_check("all 1000 pass validation", valid == 1000, "%d/1000" % valid)
	_check("all 1000 have both modes", both_modes == 1000, "%d/1000" % both_modes)
	_check("no duplicate fingerprints", fingerprints.size() == 1000, "%d unique" % fingerprints.size())
	_check("no fallback needed", fallbacks == 0, "%d fallbacks" % fallbacks)
	_check("mean obstacles per level in range", (float(total_obstacles) / 1000.0) > 3.0,
		"%.1f" % (float(total_obstacles) / 1000.0))
	print("        rejections during run: %d" % rejections)

# ---------------------------------------------------------------- worlds
func _test_world_diversity() -> void:
	print("\n-- world diversity")
	var gen := LevelGenerator.new()
	var seen := {}
	var consecutive_repeats := 0
	var prev := ""
	for i in 60:
		var lvl: Dictionary = gen.generate(i)
		seen[lvl["theme"]] = int(seen.get(lvl["theme"], 0)) + 1
		if lvl["theme"] == prev:
			consecutive_repeats += 1
		prev = lvl["theme"]
	_check("all 8 worlds appear", seen.size() == 8, "%d worlds" % seen.size())
	_check("no two consecutive levels share a world", consecutive_repeats == 0,
		"%d repeats" % consecutive_repeats)
	var wg := WorldGenerator.new()
	_check("WorldGenerator exposes 8 worlds", wg.count() == 8, "%d" % wg.count())

# ---------------------------------------------------------------- duplicates
func _test_duplicates_and_similarity() -> void:
	print("\n-- duplicate + similarity detection")
	var fm := LevelFingerprintManager.new()
	var gen := LevelGenerator.new()
	var a: Dictionary = gen.generate(3, 111)
	var b: Dictionary = a.duplicate(true)
	_check("identical spec has identical fingerprint", fm.fingerprint(a) == fm.fingerprint(b))
	var clone := a.duplicate(true)
	clone["theme"] = "neon_city"     # same layout, new paint
	_check("recoloured clone detected as similar",
		fm.similarity(fm.structural(a), fm.structural(clone)) >= GenerationConfig.SIMILARITY_LIMIT,
		"%.3f" % fm.similarity(fm.structural(a), fm.structural(clone)))
	var other := LevelGenerator.new().generate(31, 777)
	_check("different level is not flagged similar",
		fm.similarity(fm.structural(a), fm.structural(other)) < GenerationConfig.SIMILARITY_LIMIT,
		"%.3f" % fm.similarity(fm.structural(a), fm.structural(other)))

	var ar := AntiRepetitionManager.new()
	ar.accept(a)
	_check("exact duplicate rejected", ar.rejection_reason(b) != "", ar.rejection_reason(b))

# ---------------------------------------------------------------- routes
func _test_route_validation() -> void:
	print("\n-- route validation (character + vehicle)")
	var gen := LevelGenerator.new()
	var char_ok := 0
	var veh_ok := 0
	var bands := 0
	for i in 200:
		var lvl: Dictionary = gen.generate(i)
		var v := LevelValidator.new()
		var char_passable := true
		var veh_passable := true
		for band in v._bands(lvl["obstacles"]).values():
			bands += 1
			var mode := "character"
			for o in band:
				if o.get("mode", "character") == "vehicle":
					mode = "vehicle"
			if not v._band_passable(band, lvl):
				if mode == "vehicle":
					veh_passable = false
				else:
					char_passable = false
		if char_passable:
			char_ok += 1
		if veh_passable:
			veh_ok += 1
	_check("character lanes passable in all levels", char_ok == 200, "%d/200" % char_ok)
	_check("vehicle lanes passable in all levels", veh_ok == 200, "%d/200" % veh_ok)
	_check("obstacle bands were inspected", bands > 500, "%d bands" % bands)
	var lvl0: Dictionary = LevelGenerator.new().generate(0)
	_check("vehicle sections are continuous road",
		lvl0["segments"].filter(func(s): return s["mode"] == "vehicle").all(
			func(s): return float(s["length"]) >= 20.0))

# ---------------------------------------------------------------- difficulty
func _test_difficulty_progression() -> void:
	print("\n-- difficulty progression")
	var dm := DifficultyManager.new()
	var start := dm.difficulty
	var prev := start
	var monotonic := true
	var gaps: Array = []
	for i in 40:
		var d := dm.next(true)
		if d < prev - 0.0001:
			monotonic = false
		gaps.append(dm.min_obstacle_gap())
		prev = d
	_check("difficulty rises with clean runs", monotonic and dm.difficulty > start,
		"%.2f -> %.2f" % [start, dm.difficulty])
	_check("difficulty is clamped at the ceiling", dm.difficulty <= GenerationConfig.DIFFICULTY_MAX,
		"%.2f" % dm.difficulty)
	_check("obstacle gap shrinks as difficulty rises", gaps[0] >= gaps[gaps.size() - 1],
		"%.1f -> %.1f" % [gaps[0], gaps[gaps.size() - 1]])
	var dm2 := DifficultyManager.new()
	dm2.set_difficulty(0.5)
	var before := dm2.difficulty
	dm2.next(false, 3)
	_check("deaths slow the curve", dm2.difficulty - before < GenerationConfig.DIFFICULTY_PER_LEVEL,
		"%.3f" % (dm2.difficulty - before))

# ---------------------------------------------------------------- rejection
func _test_invalid_rejection() -> void:
	print("\n-- invalid level rejection")
	var v := LevelValidator.new()
	var good: Dictionary = LevelGenerator.new().generate(5)

	var blocked := good.duplicate(true)
	blocked["obstacles"] = []
	for lane in GenerationConfig.LANE_X:
		blocked["obstacles"].append({"pos": Vector3(lane, 0.9, -60.0),
			"size": Vector3(2.6, 1.8, 1.2), "kind": "barrier"})
	_check("wall of obstacles across every lane rejected", not v.is_valid(blocked),
		str(v.validate(blocked)))

	var spawn_hit := good.duplicate(true)
	spawn_hit["obstacles"] = [{"pos": Vector3(0, 0.6, -2.0), "size": Vector3(2, 1.2, 1.2), "kind": "barrier"}]
	_check("obstacle in spawn zone rejected", not v.is_valid(spawn_hit), str(v.validate(spawn_hit)))

	var off_track := good.duplicate(true)
	off_track["obstacles"] = [{"pos": Vector3(9.0, 0.6, -60.0), "size": Vector3(2, 1.2, 1.2), "kind": "barrier"}]
	_check("obstacle outside the track rejected", not v.is_valid(off_track), str(v.validate(off_track)))

	var no_modes := good.duplicate(true)
	for seg in no_modes["segments"]:
		seg["mode"] = "character"
	no_modes["obstacles"] = []
	_check("level without a vehicle section rejected", not v.is_valid(no_modes), str(v.validate(no_modes)))

	var too_short := good.duplicate(true)
	too_short["length"] = 30.0
	too_short["finish"] = Vector3(0, 1.0, -25.0)
	_check("track too short rejected", not v.is_valid(too_short), str(v.validate(too_short)))

# ---------------------------------------------------------------- fallback
func _test_bounded_retry_and_fallback() -> void:
	print("\n-- bounded retry + fallback")
	var gen := LevelGenerator.new()
	gen.validator = AlwaysInvalid.new()
	var lvl: Dictionary = gen.generate(12)
	_check("retries are bounded", gen.last_attempts <= GenerationConfig.MAX_GENERATION_ATTEMPTS,
		"%d attempts" % gen.last_attempts)
	_check("fallback used instead of looping", gen.fallback_used)
	_check("fallback level is itself valid", LevelValidator.new().is_valid(lvl),
		str(LevelValidator.new().validate(lvl)))
	_check("fallback is named as such", String(lvl["name"]).begins_with("Fallback"), lvl["name"])

# ---------------------------------------------------------------- memory
func _test_memory_cleanup() -> void:
	print("\n-- memory cleanup")
	var tm := LevelTransitionManager.new()
	var nodes: Array = []
	for i in 20:
		var n := Node3D.new()
		get_root().add_child(n)
		nodes.append(n)
		tm.push(-float(i) * 50.0, n)
	var before := tm.active_count()
	tm.evict_behind(-900.0)
	var after := tm.active_count()
	await process_frame
	await process_frame
	var alive := 0
	for n in nodes:
		if is_instance_valid(n):
			alive += 1
	_check("eviction reduces tracked segments", after < before, "%d -> %d" % [before, after])
	_check("evicted nodes are actually freed", alive <= after + 1, "%d alive of 20" % alive)
	_check("peak tracked stays bounded", tm.peak_count() <= 20, "%d" % tm.peak_count())
	tm.clear()

func _test_history_bounds() -> void:
	print("\n-- history bounds")
	var gen := LevelGenerator.new()
	for i in 700:
		gen.generate(i)
	var st := gen.stats()
	_check("history window is capped", int(st["window"]) <= GenerationConfig.HISTORY_SIZE,
		"%d of %d generated" % [int(st["window"]), int(st["generated"])])
	_check("total generated is tracked", int(st["generated"]) >= 700, str(st["generated"]))
