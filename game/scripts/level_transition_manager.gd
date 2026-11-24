class_name LevelTransitionManager
extends RefCounted
## Owns the endless-mode level pipeline for GameManager: the level
## being played plus exactly ONE pregenerated next level (chunk
## loading). When the player finishes, advance() promotes the
## pregenerated level and generates the following one, so a transition
## never waits on generation and memory never holds more than two
## level definitions.

var generator: LevelGenerator
var current_result: Dictionary = {}
var next_result: Dictionary = {}
var level_number: int = 0

var _base_seed: int = 1

## Phase 04: optional DifficultyManager performance nudge (e.g.
## {"deaths": int, "flawless": bool}) applied when generating upcoming
## levels. Empty by default — Phase 03 behaviour is unchanged until
## the AutonomousController sets it from its PerformanceTracker.
var performance_hint: Dictionary = {}

func _init(gen: LevelGenerator = null) -> void:
	generator = gen if gen != null else LevelGenerator.new()

## Starts endless mode; returns the first level's generate() result.
func start(base_seed: int) -> Dictionary:
	_base_seed = base_seed
	level_number = 1
	current_result = generator.generate(1, _seed_for(1), performance_hint)
	next_result = generator.generate(2, _seed_for(2), performance_hint)
	return current_result

## Promotes the pregenerated level; returns it as the new current.
func advance() -> Dictionary:
	if next_result.is_empty():
		start(_base_seed)
		return current_result
	current_result = next_result
	level_number = int(current_result["level"].get("level_number", level_number + 1))
	next_result = generator.generate(level_number + 1, _seed_for(level_number + 1), performance_hint)
	return current_result

## How many level definitions are currently retained (must stay <= 2).
func retained_count() -> int:
	var n: int = 0
	if not current_result.is_empty():
		n += 1
	if not next_result.is_empty():
		n += 1
	return n

func _seed_for(n: int) -> int:
	return _base_seed + n * 1009
