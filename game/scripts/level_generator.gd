class_name LevelGenerator
extends RefCounted
## The Phase 03 orchestration point. generate() builds one level end
## to end, locally and deterministically from a seed (no external AI
## API anywhere):
##
##   seed -> DifficultyManager profile -> WorldGenerator world pick
##        -> RouteGenerator plan -> SegmentGenerator content
##        -> LevelValidator -> AntiRepetitionManager vs history
##
## A candidate that fails validation or repetition checks is
## regenerated with a derived seed, at most GenerationConfig.max_retries
## times. If every attempt fails, a guaranteed-valid fallback template
## is served instead (and counted) — generation NEVER loops forever
## and NEVER returns an invalid level.
##
## Also hosts a small generation queue: callers enqueue upcoming level
## numbers and drain them with a per-call budget, which is how chunk
## loading stays frame-friendly (only current + next levels are kept
## by LevelTransitionManager).

var config: GenerationConfig
var difficulty_manager := DifficultyManager.new()
var world_generator: WorldGenerator
var history: LevelHistoryManager
var anti_repetition: AntiRepetitionManager
var validator: LevelValidator

var _routes: RouteGenerator
var _segments := SegmentGenerator.new()

var total_generated: int = 0
var total_attempts: int = 0
var fallbacks_used: int = 0
var validation_rejections: int = 0
## Phase 09 — the fallback template is hand-built to be valid, but
## nothing used to check that. It is now validated before serving;
## a failure here means the template itself regressed, so it is
## counted loudly (the level is still served — availability —
## and the reliability suite asserts this stays 0).
var fallback_validation_failures: int = 0

var _queue: Array[Dictionary] = []

func _init(env_manager: EnvironmentManager = null, cfg: GenerationConfig = null) -> void:
	config = cfg if cfg != null else GenerationConfig.new()
	world_generator = WorldGenerator.new(env_manager)
	history = LevelHistoryManager.new(config)
	anti_repetition = AntiRepetitionManager.new(config, history)
	validator = LevelValidator.new(config)
	_routes = RouteGenerator.new(config)

## --- Main entry point -------------------------------------------------
## Returns {ok, level, meta:{seed, world, fingerprint, attempts,
## max_similarity, difficulty_index, fallback}}.
func generate(level_number: int, base_seed: int, performance: Dictionary = {}) -> Dictionary:
	var difficulty: Dictionary = difficulty_manager.profile_for(level_number, performance)
	var last_meta: Dictionary = {}
	for attempt in range(config.max_retries + 1):
		total_attempts += 1
		var attempt_seed: int = base_seed * 100003 + attempt * 7919 + level_number * 131
		var built: Dictionary = _build_candidate(level_number, attempt_seed, difficulty)
		var level: Dictionary = built["level"]
		var check: Dictionary = validator.validate(level, difficulty)
		if not bool(check["valid"]):
			validation_rejections += 1
			last_meta = {"seed": attempt_seed, "errors": check["errors"]}
			continue
		var evaluation: Dictionary = anti_repetition.evaluate(level)
		last_meta = {"seed": attempt_seed, "world": str(level["world"]),
			"fingerprint": str(evaluation["fingerprint"]),
			"max_similarity": float(evaluation["max_similarity"])}
		if bool(evaluation["accepted"]):
			anti_repetition.commit(level, evaluation)
			total_generated += 1
			return {"ok": true, "level": level, "meta": {
				"seed": attempt_seed, "world": str(level["world"]),
				"fingerprint": str(evaluation["fingerprint"]),
				"attempts": attempt + 1,
				"max_similarity": float(evaluation["max_similarity"]),
				"difficulty_index": float(difficulty["index"]),
				"fallback": false}}
	# All bounded attempts rejected: serve the fallback template.
	var fallback: Dictionary = _build_fallback(level_number, base_seed, difficulty)
	var fb_check: Dictionary = validator.validate(fallback, difficulty)
	var fb_valid := bool(fb_check["valid"])
	if not fb_valid:
		fallback_validation_failures += 1
	var fb_eval: Dictionary = anti_repetition.evaluate(fallback)
	anti_repetition.commit(fallback, fb_eval)
	fallbacks_used += 1
	total_generated += 1
	return {"ok": true, "level": fallback, "meta": {
		"seed": base_seed, "world": str(fallback["world"]),
		"fingerprint": str(fb_eval["fingerprint"]),
		"attempts": config.max_retries + 1,
		"max_similarity": float(last_meta.get("max_similarity", 1.0)),
		"difficulty_index": float(difficulty["index"]),
		"fallback": true, "fallback_valid": fb_valid}}

## --- Generation queue (chunked / budgeted) ------------------------------
func enqueue(level_number: int, base_seed: int) -> void:
	_queue.append({"level_number": level_number, "seed": base_seed})

func pending() -> int:
	return _queue.size()

## Generates at most `budget` queued levels; returns their results.
func process_queue(budget: int) -> Array:
	var out: Array = []
	var n: int = mini(budget, _queue.size())
	for i in n:
		var job: Dictionary = _queue.pop_front()
		out.append(generate(int(job["level_number"]), int(job["seed"])))
	return out

## --- Internals -----------------------------------------------------------

func _build_candidate(level_number: int, seed: int, difficulty: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var world_name: String = world_generator.select_world(rng, history)
	var world_cfg: Dictionary = world_generator.world_config(world_name)
	var segment_count: int = clampi(
		rng.randi_range(config.min_segments_per_level, config.max_segments_per_level)
		+ int(difficulty["segment_count_bonus"]),
		config.min_segments_per_level, config.max_segments_per_level)
	var route: Dictionary = _routes.plan(rng, difficulty, segment_count, true)
	return {"level": _assemble(level_number, seed, rng, world_name, world_cfg, route, difficulty)}

func _assemble(level_number: int, seed: int, rng: RandomNumberGenerator,
		world_name: String, world_cfg: Dictionary, route: Dictionary,
		difficulty: Dictionary) -> Dictionary:
	var width: float = float(world_cfg["width"])
	var ctx: Dictionary = {"last_obstacle_z": 1e9, "pad_z": float(route["vehicle_pad_z"])}
	var level: Dictionary = {
		"name": "Level %d — %s" % [level_number, world_name],
		"theme": world_name, "world": world_name,
		"start_mode": str(route["start_mode"]),
		"length": float(route["total_length"]), "width": width,
		"seed": seed, "level_number": level_number, "generated": true,
		"decor_count": world_generator.decor_count(world_name, rng),
		"obstacles": [], "collectibles": [], "platforms": [], "moving_platforms": [],
		"gates": [], "rails": [], "tunnel_arches": [], "gaps": [],
		"ground_strips": [], "path_strips": [],
		"vehicle_pad_z": float(route["vehicle_pad_z"]),
		"segments": route["segments"],
		"theme_data": world_generator.build_theme(world_name, rng),
	}
	# Spawn apron (z +10 -> first segment) and finish apron (course end
	# -> past the finish zone) so the road is continuous end to end.
	var course_end: float = -float(route["total_length"]) + config.finish_safe_distance + 8.0
	(level["ground_strips"] as Array).append(
		{"z_center": -0.5, "len": 21.0, "x": 0.0, "w": width + 30.0})
	(level["path_strips"] as Array).append(
		{"z_center": -0.5, "len": 21.0, "x": 0.0, "w": width})
	(level["ground_strips"] as Array).append(
		{"z_center": course_end - 7.0, "len": 14.0, "x": 0.0, "w": width + 30.0})
	(level["path_strips"] as Array).append(
		{"z_center": course_end - 7.0, "len": 14.0, "x": 0.0, "w": width})
	for seg in route["segments"]:
		var content: Dictionary = _segments.build_segment(rng, seg, difficulty, ctx, width)
		for key in ["obstacles", "collectibles", "platforms", "moving_platforms",
				"gates", "rails", "tunnel_arches", "gaps", "ground_strips", "path_strips"]:
			(level[key] as Array).append_array(content[key])
	return level

## Guaranteed-valid fallback: a short, sparse, fixed-shape level whose
## obstacles are hand-spaced far beyond every validator minimum. Used
## only when bounded retries are exhausted; counted in fallbacks_used.
func _build_fallback(level_number: int, seed: int, difficulty: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 17
	var names: Array[String] = WorldGenerator.world_names()
	var world_name: String = names[level_number % names.size()]
	var world_cfg: Dictionary = world_generator.world_config(world_name)
	var width: float = float(world_cfg["width"])
	var segments: Array[Dictionary] = [
		{"index": 0, "mode": "character", "feature": "run", "length": 26.0,
			"start_z": -11.0, "lane_offset": 0.0, "transition": false},
		{"index": 1, "mode": "vehicle", "feature": "gates", "length": 26.0,
			"start_z": -37.0, "lane_offset": 0.0, "transition": true},
	]
	var level: Dictionary = {
		"name": "Level %d — %s (fallback)" % [level_number, world_name],
		"theme": world_name, "world": world_name, "start_mode": "character",
		"length": 78.0, "width": width, "seed": seed,
		"level_number": level_number, "generated": true, "fallback": true,
		"decor_count": 14,
		"obstacles": [
			{"type": "jump", "x": 0.0, "z": -22.0},
			{"type": "block", "x": 3.0, "z": -48.0},
		],
		"collectibles": [Vector3(0, 1.0, -16), Vector3(0, 1.0, -30), Vector3(0, 1.0, -58)],
		"platforms": [], "moving_platforms": [],
		"gates": [{"x": 0.0, "z": -44.0}, {"x": 0.0, "z": -56.0}],
		"rails": [], "tunnel_arches": [], "gaps": [],
		"ground_strips": [{"z_center": -34.0, "len": 88.0, "x": 0.0, "w": width + 30.0}],
		"path_strips": [{"z_center": -34.0, "len": 88.0, "x": 0.0, "w": width}],
		"vehicle_pad_z": -40.0,
		"segments": segments,
		"theme_data": world_generator.build_theme(world_name, rng),
	}
	return level
