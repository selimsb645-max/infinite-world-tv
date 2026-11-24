class_name LevelGenerator
extends RefCounted
## LevelGenerator - the orchestrator. One call in, one playable level Dictionary out.
##
## Order matters and is the whole design:
##   seed -> world -> route -> obstacles -> validate -> anti-repeat -> accept
## A level that fails validation or looks like a recent one is discarded and regenerated with
## a derived seed. After MAX_GENERATION_ATTEMPTS the generator falls back to a known-good
## template instead of looping forever, because an infinite game must never stall.

var config: GenerationConfig
var worlds: WorldGenerator
var segments: SegmentGenerator
var obstacles: ObstacleGenerator
var routes: RouteGenerator
var env: EnvironmentGenerator
var validator: LevelValidator
var anti_repeat: AntiRepetitionManager
var difficulty: DifficultyManager

var last_attempts: int = 0
var last_rejections: Array = []
var fallback_used: bool = false

func _init() -> void:
	config = GenerationConfig.new()
	worlds = WorldGenerator.new()
	segments = SegmentGenerator.new()
	obstacles = ObstacleGenerator.new()
	routes = RouteGenerator.new()
	env = EnvironmentGenerator.new()
	validator = LevelValidator.new()
	anti_repeat = AntiRepetitionManager.new()
	difficulty = DifficultyManager.new()

func reset() -> void:
	anti_repeat.reset()
	difficulty.reset()
	last_attempts = 0
	last_rejections.clear()
	fallback_used = false

## Generate level number `index` (0-based). Deterministic for a given seed and index.
func generate(index: int, seed_value: int = -1) -> Dictionary:
	last_attempts = 0
	last_rejections.clear()
	fallback_used = false
	var base_seed := seed_value if seed_value >= 0 else index * 7919 + 104729
	var previous_world := ""
	var recent := anti_repeat.history.recent_worlds(1)
	if not recent.is_empty():
		previous_world = String(recent[0])
	var d := difficulty.difficulty
	for attempt in GenerationConfig.MAX_GENERATION_ATTEMPTS:
		last_attempts = attempt + 1
		var rng := RandomNumberGenerator.new()
		rng.seed = base_seed + attempt * 104729
		var spec := _build(index, rng, d, previous_world)
		var problems := validator.validate(spec)
		if not problems.is_empty():
			last_rejections.append({"reason": "invalid", "problems": problems})
			anti_repeat.reject()
			continue
		var reason := anti_repeat.rejection_reason(spec)
		if reason != "":
			last_rejections.append({"reason": reason})
			anti_repeat.reject()
			continue
		anti_repeat.accept(spec)
		return spec
	# bounded retry exhausted: never stall an infinite game
	fallback_used = true
	var fb := _fallback(index, base_seed)
	anti_repeat.accept(fb)
	return fb

func _build(index: int, rng: RandomNumberGenerator, d: float, previous_world: String) -> Dictionary:
	var world_id := worlds.pick(index, rng, previous_world)
	var world := worlds.get_world(world_id)
	var scaled := clampf(d * float(world.get("difficulty_scale", 1.0)),
		GenerationConfig.DIFFICULTY_MIN, GenerationConfig.DIFFICULTY_MAX)
	var target_len := difficulty.level_length()
	var route := routes.build(world, scaled, target_len, rng, segments)
	var budget := difficulty.obstacle_budget()
	var min_gap := difficulty.min_obstacle_gap()
	var kinds: Array = world.get("obstacle_kinds", ["barrier"])
	var all_obstacles: Array = []
	for seg in route:
		var per_seg := maxi(1, int(round(float(budget) / maxf(1.0, float(route.size())))))
		var placed := obstacles.place(seg, kinds, per_seg, min_gap, rng)
		for o in placed:
			all_obstacles.append(o)
	# flatten to the Phase 02 shape: pos + size only
	var flat: Array = []
	for o in all_obstacles:
		flat.append({"pos": o["pos"], "size": o["size"], "kind": o["kind"]})
	var length := absf(float(route[route.size() - 1]["end_z"]))
	var spec := {
		"id": index + 1,
		"name": "%s %d" % [String(world.get("label", world_id)), index + 1],
		"theme": world_id,
		"world": world_id,
		"terrain": world.get("terrain", "flat"),
		"length": length,
		"spawn": Vector3(0, 1.0, 0.0),
		"vehicle_spawn": Vector3(0, 1.0, 12.0),
		"finish": Vector3(0, 1.0, -(length - 5.0)),
		"obstacles": flat,
		"segments": route,
		"environment": env.variation(world_id, rng),
		"difficulty": scaled,
		"seed": rng.seed,
	}
	spec["fingerprint"] = anti_repeat.fingerprint_manager.fingerprint(spec)
	return spec

## Known-good template used only when bounded retries fail. Guaranteed to validate.
func _fallback(index: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var route := [
		segments.build("run", 0.0, 0.3, rng),
		segments.build("road", -40.0, 0.3, rng),
		segments.build("run", -110.0, 0.2, rng),
	]
	var length := absf(float(route[route.size() - 1]["end_z"]))
	var spec := {
		"id": index + 1, "name": "Fallback Circuit %d" % (index + 1),
		"theme": "green_valley", "world": "green_valley", "terrain": "rolling_hills",
		"length": length, "spawn": Vector3(0, 1.0, 0.0), "vehicle_spawn": Vector3(0, 1.0, 12.0),
		"finish": Vector3(0, 1.0, -(length - 5.0)),
		"obstacles": [
			{"pos": Vector3(-2.4, 0.6, -20.0), "size": Vector3(2.0, 1.2, 1.2), "kind": "barrier"},
			{"pos": Vector3(2.4, 0.6, -60.0), "size": Vector3(2.0, 1.2, 1.2), "kind": "barrier"},
		],
		"segments": route,
		"environment": env.variation("green_valley", rng),
		"difficulty": 0.3, "seed": seed_value,
	}
	spec["fingerprint"] = anti_repeat.fingerprint_manager.fingerprint(spec)
	return spec

func stats() -> Dictionary:
	return anti_repeat.stats()
