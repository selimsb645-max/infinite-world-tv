class_name DifficultyManager
extends RefCounted
## DifficultyManager - a single number in [0.05, 0.95] that every other generator reads.
##
## It rises with the level index, is nudged by how the player actually performed (clean
## clears speed it up, deaths slow it down) and is clamped so no level is ever unfair.

var level_index: int = 0
var performance: float = 1.0     # 1.0 = clean, 0.0 = struggling
var difficulty: float = GenerationConfig.DIFFICULTY_MIN

func reset() -> void:
	level_index = 0
	performance = 1.0
	difficulty = GenerationConfig.DIFFICULTY_MIN

func next(clean_run: bool, deaths: int = 0) -> float:
	level_index += 1
	var delta := GenerationConfig.DIFFICULTY_PER_LEVEL
	if clean_run:
		delta *= 1.35
	if deaths > 0:
		delta *= maxf(0.25, 1.0 - 0.25 * float(deaths))
	performance = clampf(1.0 - 0.2 * float(deaths), 0.0, 1.0)
	difficulty = clampf(difficulty + delta, GenerationConfig.DIFFICULTY_MIN, GenerationConfig.DIFFICULTY_MAX)
	return difficulty

func set_difficulty(value: float) -> void:
	difficulty = clampf(value, GenerationConfig.DIFFICULTY_MIN, GenerationConfig.DIFFICULTY_MAX)

## Minimum spacing between obstacles at the current difficulty (reaction time budget).
func min_obstacle_gap() -> float:
	var t := inverse_lerp(GenerationConfig.DIFFICULTY_MIN, GenerationConfig.DIFFICULTY_MAX, difficulty)
	return lerpf(GenerationConfig.MIN_OBSTACLE_GAP_EASY, GenerationConfig.MIN_OBSTACLE_GAP_HARD, clampf(t, 0.0, 1.0))

func obstacle_budget() -> int:
	var t := inverse_lerp(GenerationConfig.DIFFICULTY_MIN, GenerationConfig.DIFFICULTY_MAX, difficulty)
	return int(round(lerpf(6.0, float(GenerationConfig.MAX_OBSTACLES), clampf(t, 0.0, 1.0))))

func level_length() -> float:
	# longer runs as difficulty grows, still bounded so a level never drags
	return clampf(200.0 + 30.0 * float(level_index), 200.0, 420.0)
