class_name LevelManager
extends Node
## Handcrafted Phase 02 test levels. Data only — WorldManager builds
## the geometry. The infinite procedural generator is a later phase
## and is intentionally NOT implemented here.
##
## Coordinates: the course runs along -Z. Ground spans z in [-length, 10].
## Obstacle types: "jump" (low barrier, jump over), "slide" (high barrier
## with a gap underneath, slide under), "block" (solid, must steer around).

const LEVELS: Array = [
	{
		"name": "Level 1 — Valley Run",
		"theme": "Green Valley",
		"start_mode": "character",
		"length": 120.0,
		"width": 14.0,
		"seed": 101,
		"decor_count": 26,
		"obstacles": [
			{"type": "jump", "x": 0.0, "z": -25.0},
			{"type": "slide", "x": 0.0, "z": -45.0},
			{"type": "block", "x": -2.5, "z": -65.0},
			{"type": "jump", "x": 2.0, "z": -82.0},
			{"type": "slide", "x": -1.0, "z": -100.0},
		],
		"collectibles": [
			Vector3(0, 1.0, -15), Vector3(0, 1.0, -35), Vector3(2, 1.0, -55),
			Vector3(-2, 1.0, -75), Vector3(0, 1.0, -92), Vector3(0, 1.0, -110),
		],
		"vehicle_pad_z": -58.0,
	},
	{
		"name": "Level 2 — Neon Drive",
		"theme": "Neon City",
		"start_mode": "vehicle",
		"length": 160.0,
		"width": 18.0,
		"seed": 202,
		"decor_count": 30,
		"obstacles": [
			{"type": "block", "x": -3.0, "z": -35.0},
			{"type": "block", "x": 3.0, "z": -60.0},
			{"type": "block", "x": 0.0, "z": -85.0},
			{"type": "block", "x": -4.0, "z": -115.0},
			{"type": "block", "x": 4.0, "z": -140.0},
		],
		"collectibles": [
			Vector3(0, 1.0, -20), Vector3(-2, 1.0, -48), Vector3(2, 1.0, -72),
			Vector3(0, 1.0, -100), Vector3(0, 1.0, -128), Vector3(0, 1.0, -150),
		],
		"vehicle_pad_z": -10.0,
	},
	{
		"name": "Level 3 — Theme Tour",
		"theme": "Desert World",
		"start_mode": "character",
		"length": 100.0,
		"width": 14.0,
		"seed": 303,
		"decor_count": 20,
		"obstacles": [
			{"type": "jump", "x": 0.0, "z": -22.0},
			{"type": "block", "x": 2.5, "z": -48.0},
			{"type": "slide", "x": 0.0, "z": -70.0},
			{"type": "jump", "x": -2.0, "z": -88.0},
		],
		"collectibles": [
			Vector3(0, 1.0, -12), Vector3(0, 1.0, -35), Vector3(-2, 1.0, -60),
			Vector3(0, 1.0, -80), Vector3(0, 1.0, -95),
		],
		"vehicle_pad_z": -40.0,
	},
]

var current_index: int = 0

func level_count() -> int:
	return LEVELS.size()

func get_level(index: int) -> Dictionary:
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]

func current_level() -> Dictionary:
	return get_level(current_index)

func set_current(index: int) -> Dictionary:
	current_index = clampi(index, 0, LEVELS.size() - 1)
	return current_level()

func next_index() -> int:
	return (current_index + 1) % LEVELS.size()
