class_name WorldGenerator
extends RefCounted
## Registry of the eight INFINITE WORLD TV worlds and the factory for
## their per-level theme data. The five Phase 02 worlds keep their
## EnvironmentManager themes; Phase 03 adds Ocean World, Fantasy
## Islands and Futuristic Highway (themes also live in
## EnvironmentManager.THEMES, decor styles in WorldManager).
##
## Adding a ninth world = one entry in WORLDS + one theme + one decor
## style; nothing else changes (configurable architecture).

const WORLDS: Array[Dictionary] = [
	{"name": "Green Valley", "width": 14.0, "decor_count": 26, "bias": "mixed"},
	{"name": "Neon City", "width": 18.0, "decor_count": 30, "bias": "vehicle"},
	{"name": "Desert World", "width": 14.0, "decor_count": 20, "bias": "mixed"},
	{"name": "Snow Mountain", "width": 14.0, "decor_count": 24, "bias": "character"},
	{"name": "Space World", "width": 16.0, "decor_count": 22, "bias": "mixed"},
	{"name": "Ocean World", "width": 16.0, "decor_count": 24, "bias": "character"},
	{"name": "Fantasy Islands", "width": 15.0, "decor_count": 28, "bias": "mixed"},
	{"name": "Futuristic Highway", "width": 18.0, "decor_count": 26, "bias": "vehicle"},
]

var _environments := EnvironmentGenerator.new()
var _env_manager: EnvironmentManager

func _init(env_manager: EnvironmentManager = null) -> void:
	# EnvironmentManager is only used as a theme-data source; a bare
	# instance (never added to the tree) is enough for headless use.
	_env_manager = env_manager if env_manager != null else EnvironmentManager.new()

static func world_names() -> Array[String]:
	var out: Array[String] = []
	for w in WORLDS:
		out.append(str(w["name"]))
	return out

func world_config(world_name: String) -> Dictionary:
	for w in WORLDS:
		if str(w["name"]) == world_name:
			return w
	return WORLDS[0]

func has_world(world_name: String) -> bool:
	for w in WORLDS:
		if str(w["name"]) == world_name:
			return true
	return false

## Picks the next world, avoiding an immediate repeat of the previous
## world and preferring worlds not seen in the recent history window.
func select_world(rng: RandomNumberGenerator, history: LevelHistoryManager) -> String:
	var names: Array[String] = world_names()
	var recent: Array[String] = history.recent_worlds(6)
	var pool: Array[String] = []
	for n in names:
		if not recent.has(n):
			pool.append(n)
	if pool.is_empty():
		pool = names.duplicate()
		if recent.size() > 0:
			pool.erase(recent[recent.size() - 1])
	return pool[rng.randi_range(0, pool.size() - 1)]

## Full theme dict for WorldManager, with per-level variation applied.
func build_theme(world_name: String, rng: RandomNumberGenerator) -> Dictionary:
	var base: Dictionary = _env_manager.theme_data(world_name)
	return _environments.vary_theme(base, rng)

func decor_count(world_name: String, rng: RandomNumberGenerator) -> int:
	return _environments.decor_count(rng, int(world_config(world_name)["decor_count"]))
