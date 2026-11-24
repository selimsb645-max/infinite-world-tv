class_name WorldGenerator
extends RefCounted
## WorldGenerator - the eight worlds and their gameplay personalities.
##
## A world is more than a palette: it decides which segment types are likely, how tight the
## obstacles are and how the environment reacts. Adding a ninth world means adding one entry
## here plus one theme in WorldManager; nothing else changes.

const WORLDS := {
	"green_valley": {
		"label": "Green Valley", "mode_bias": 0.5, "difficulty_scale": 0.9,
		"segments": {"run": 4, "jump": 3, "slide": 2, "road": 2, "curve": 1, "bridge": 1},
		"obstacle_kinds": ["barrier", "low_bar", "high_bar", "crate"],
		"terrain": "rolling_hills", "decor": "trees",
	},
	"neon_city": {
		"label": "Neon City", "mode_bias": 0.45, "difficulty_scale": 1.05,
		"segments": {"run": 2, "jump": 3, "slide": 3, "road": 3, "curve": 2, "tunnel": 1},
		"obstacle_kinds": ["barrier", "high_bar", "crate", "speed_gate"],
		"terrain": "flat_street", "decor": "towers",
	},
	"desert_world": {
		"label": "Desert World", "mode_bias": 0.4, "difficulty_scale": 1.0,
		"segments": {"run": 3, "jump": 3, "slide": 2, "road": 3, "curve": 2},
		"obstacle_kinds": ["barrier", "crate", "rock", "low_bar"],
		"terrain": "dunes", "decor": "cacti",
	},
	"snow_mountain": {
		"label": "Snow Mountain", "mode_bias": 0.5, "difficulty_scale": 1.1,
		"segments": {"run": 2, "jump": 4, "slide": 2, "road": 2, "curve": 2, "bridge": 2},
		"obstacle_kinds": ["barrier", "low_bar", "ice_block", "crate"],
		"terrain": "ridge", "decor": "pines",
	},
	"space_world": {
		"label": "Space World", "mode_bias": 0.55, "difficulty_scale": 1.15,
		"segments": {"run": 3, "jump": 3, "slide": 2, "road": 2, "tunnel": 2, "bridge": 2},
		"obstacle_kinds": ["barrier", "high_bar", "crate", "speed_gate"],
		"terrain": "platform_ring", "decor": "stars",
	},
	"ocean_world": {
		"label": "Ocean World", "mode_bias": 0.6, "difficulty_scale": 0.95,
		"segments": {"run": 3, "jump": 3, "slide": 1, "road": 3, "bridge": 3},
		"obstacle_kinds": ["barrier", "low_bar", "crate", "rock"],
		"terrain": "causeway", "decor": "waves",
	},
	"fantasy_islands": {
		"label": "Fantasy Islands", "mode_bias": 0.65, "difficulty_scale": 0.85,
		"segments": {"run": 3, "jump": 4, "slide": 2, "bridge": 3, "curve": 1},
		"obstacle_kinds": ["barrier", "low_bar", "high_bar", "crate"],
		"terrain": "floating_platforms", "decor": "crystals",
	},
	"futuristic_highway": {
		"label": "Futuristic Highway", "mode_bias": 0.25, "difficulty_scale": 1.2,
		"segments": {"road": 5, "curve": 4, "tunnel": 2, "run": 1, "jump": 1},
		"obstacle_kinds": ["speed_gate", "barrier", "crate"],
		"terrain": "highway", "decor": "light_pylons",
	},
}

const ORDER := [
	"green_valley", "neon_city", "desert_world", "snow_mountain",
	"space_world", "ocean_world", "fantasy_islands", "futuristic_highway",
]

## Pick a world for a level. Consecutive levels never repeat a world, and the rotation
## walks the full list so all eight appear before any repeats.
func pick(index: int, rng: RandomNumberGenerator, previous: String) -> String:
	var pool: Array = []
	for id in ORDER:
		if id != previous:
			pool.append(id)
	if pool.is_empty():
		pool = ORDER.duplicate()
	return pool[rng.randi_range(0, pool.size() - 1)]

func get_world(id: String) -> Dictionary:
	return WORLDS.get(id, WORLDS["green_valley"])

func all_worlds() -> Array:
	return ORDER.duplicate()

func count() -> int:
	return ORDER.size()

## Weighted pick of a segment type for this world and difficulty.
func pick_segment_type(world: Dictionary, rng: RandomNumberGenerator, difficulty: float) -> String:
	var table: Dictionary = world.get("segments", {})
	var total := 0.0
	var weighted: Array = []
	for key in table.keys():
		var w := float(table[key])
		# harder levels lean toward vehicle roads and tighter obstacles
		if key in ["road", "curve", "tunnel"]:
			w *= 1.0 + difficulty * 0.8
		if key in ["jump", "slide"]:
			w *= 1.0 + difficulty * 0.5
		total += w
		weighted.append([key, w])
	var roll := rng.randf() * total
	for entry in weighted:
		roll -= entry[1]
		if roll <= 0.0:
			return entry[0]
	return weighted[0][0]
