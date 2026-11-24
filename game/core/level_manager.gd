extends Node
## LevelManager - the five handcrafted Phase 02 levels.
##
## Why data and not .tscn files: a level is a plain Dictionary, so it can be validated,
## diffed and unit-tested without loading a scene tree. Phase 03's generator will emit the
## exact same shape, which means the controllers never learn where a level came from.
##
## Coordinate convention: the run goes along -Z. Ground sits at y = 0.

const LEVELS := [
	{
		"id": 1, "name": "Green Valley Sprint", "theme": "green_valley",
		"length": 220.0,
		"spawn": Vector3(0, 1.0, 0),
		"vehicle_spawn": Vector3(0, 1.0, 12),
		"finish": Vector3(0, 1.0, -215),
		"obstacles": [
			{"pos": Vector3(-2.0, 0.6, -35), "size": Vector3(2.0, 1.2, 1.2)},
			{"pos": Vector3(2.0, 0.6, -55), "size": Vector3(2.0, 1.2, 1.2)},
			{"pos": Vector3(0.0, 1.4, -78), "size": Vector3(6.0, 0.6, 1.0)},
			{"pos": Vector3(-1.5, 0.6, -120), "size": Vector3(2.0, 1.2, 1.2)},
			{"pos": Vector3(1.5, 0.6, -150), "size": Vector3(2.0, 1.2, 1.2)},
		],
	},
	{
		"id": 2, "name": "Neon City Dash", "theme": "neon_city",
		"length": 240.0,
		"spawn": Vector3(0, 1.0, 0),
		"vehicle_spawn": Vector3(0, 1.0, 12),
		"finish": Vector3(0, 1.0, -235),
		"obstacles": [
			{"pos": Vector3(0.0, 0.6, -30), "size": Vector3(2.4, 1.2, 1.2)},
			{"pos": Vector3(-2.4, 1.6, -60), "size": Vector3(2.0, 0.5, 1.0)},
			{"pos": Vector3(2.4, 1.6, -60), "size": Vector3(2.0, 0.5, 1.0)},
			{"pos": Vector3(0.0, 0.6, -95), "size": Vector3(3.0, 1.2, 1.2)},
			{"pos": Vector3(-2.0, 0.6, -140), "size": Vector3(2.0, 1.2, 1.2)},
			{"pos": Vector3(2.0, 0.6, -175), "size": Vector3(2.0, 1.2, 1.2)},
		],
	},
	{
		"id": 3, "name": "Desert World Rally", "theme": "desert_world",
		"length": 260.0,
		"spawn": Vector3(0, 1.0, 0),
		"vehicle_spawn": Vector3(0, 1.0, 12),
		"finish": Vector3(0, 1.0, -255),
		"obstacles": [
			{"pos": Vector3(-2.0, 0.8, -40), "size": Vector3(1.8, 1.6, 1.8)},
			{"pos": Vector3(2.0, 0.8, -40), "size": Vector3(1.8, 1.6, 1.8)},
			{"pos": Vector3(0.0, 1.5, -70), "size": Vector3(7.0, 0.6, 1.0)},
			{"pos": Vector3(0.0, 0.8, -110), "size": Vector3(1.8, 1.6, 1.8)},
			{"pos": Vector3(-2.2, 0.8, -160), "size": Vector3(1.8, 1.6, 1.8)},
			{"pos": Vector3(2.2, 0.8, -195), "size": Vector3(1.8, 1.6, 1.8)},
		],
	},
	{
		"id": 4, "name": "Snow Mountain Run", "theme": "snow_mountain",
		"length": 230.0,
		"spawn": Vector3(0, 1.0, 0),
		"vehicle_spawn": Vector3(0, 1.0, 12),
		"finish": Vector3(0, 1.0, -225),
		"obstacles": [
			{"pos": Vector3(1.8, 0.7, -32), "size": Vector3(2.2, 1.4, 1.4)},
			{"pos": Vector3(-1.8, 0.7, -52), "size": Vector3(2.2, 1.4, 1.4)},
			{"pos": Vector3(0.0, 1.8, -85), "size": Vector3(5.5, 0.5, 1.0)},
			{"pos": Vector3(-2.0, 0.7, -130), "size": Vector3(2.2, 1.4, 1.4)},
			{"pos": Vector3(2.0, 0.7, -170), "size": Vector3(2.2, 1.4, 1.4)},
		],
	},
	{
		"id": 5, "name": "Space World Circuit", "theme": "space_world",
		"length": 250.0,
		"spawn": Vector3(0, 1.0, 0),
		"vehicle_spawn": Vector3(0, 1.0, 12),
		"finish": Vector3(0, 1.0, -245),
		"obstacles": [
			{"pos": Vector3(0.0, 0.7, -28), "size": Vector3(2.6, 1.4, 1.4)},
			{"pos": Vector3(-2.6, 1.7, -58), "size": Vector3(1.8, 0.5, 1.0)},
			{"pos": Vector3(2.6, 1.7, -58), "size": Vector3(1.8, 0.5, 1.0)},
			{"pos": Vector3(0.0, 0.7, -100), "size": Vector3(3.2, 1.4, 1.4)},
			{"pos": Vector3(-2.2, 0.7, -150), "size": Vector3(2.0, 1.4, 1.4)},
			{"pos": Vector3(2.2, 0.7, -185), "size": Vector3(2.0, 1.4, 1.4)},
		],
	},
]

## Phase 03: handcrafted levels stay as the intro, then the generator takes over forever.
var generator: LevelGenerator
var endless: bool = false
var generated_cache: Dictionary = {}

func _ready() -> void:
	if generator == null:
		generator = LevelGenerator.new()

func level_count() -> int:
	return LEVELS.size()

func get_level(index: int) -> Dictionary:
	if endless and index >= LEVELS.size():
		return generated_level(index)
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]

## Generate (and cache) the endless level for this index. Deterministic per index.
func generated_level(index: int) -> Dictionary:
	if generator == null:
		generator = LevelGenerator.new()
	if not generated_cache.has(index):
		# keep difficulty in step with how far the player has come
		generator.difficulty.set_difficulty(
			clampf(GenerationConfig.DIFFICULTY_MIN + GenerationConfig.DIFFICULTY_PER_LEVEL * float(index),
				GenerationConfig.DIFFICULTY_MIN, GenerationConfig.DIFFICULTY_MAX))
		generated_cache[index] = generator.generate(index)
		# bounded cache: an endless session must not grow without limit
		if generated_cache.size() > 12:
			var oldest: Variant = generated_cache.keys()[0]
			generated_cache.erase(oldest)
	return generated_cache[index]

func generation_stats() -> Dictionary:
	if generator == null:
		return {}
	return generator.stats()

## Phase 03 will replace this with generated levels; the contract stays identical.
func validate(level: Dictionary) -> bool:
	if not level.has("spawn") or not level.has("finish") or not level.has("theme"):
		return false
	if (level["finish"] as Vector3).z >= (level["spawn"] as Vector3).z:
		return false
	return true
