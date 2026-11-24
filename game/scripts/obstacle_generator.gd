class_name ObstacleGenerator
extends RefCounted
## Picks obstacle placements for one segment, honouring the difficulty
## profile's spacing and the world's obstacle flavour weights. All
## positions are absolute level coordinates (course runs along -Z,
## route lane centre = segment lane_offset).
##
## Character obstacles use the Phase 02 types: "jump" (low barrier),
## "slide" (high barrier with gap under), "block" (steer around).
## Vehicle sections use "block" road obstacles plus non-colliding
## "gate" speed gates. Generation-time spacing is enforced here; the
## LevelValidator re-checks it independently.

const CHARACTER_TYPES: Array[String] = ["jump", "slide", "block"]

## Fills ctx (shared across segments of one level):
##   ctx.last_obstacle_z — z of the most recent obstacle placed
##   ctx.pad_z — mode-transition pad z (kept clear)
## Returns Array of obstacle dicts {type, x, z}.
func obstacles_for_segment(rng: RandomNumberGenerator, segment: Dictionary,
		difficulty: Dictionary, ctx: Dictionary, width: float) -> Array:
	var out: Array = []
	var mode: String = str(segment["mode"])
	var feature: String = str(segment["feature"])
	var lane: float = float(segment["lane_offset"])
	var start_z: float = float(segment["start_z"])
	var seg_len: float = float(segment["length"])
	var count: int = int(difficulty["obstacles_per_segment"])
	if feature in ["gap", "bridge", "tunnel"]:
		count = maxi(1, count - 2)
	if feature == "gates":
		count = maxi(1, count - 2)
	var min_spacing: float = float(difficulty["min_spacing"])
	var cursor: float = start_z - rng.randf_range(3.0, 6.0)
	var last_z: float = float(ctx.get("last_obstacle_z", 1e9))
	for i in count:
		if cursor < start_z - seg_len + 4.0:
			break
		if last_z - cursor < min_spacing:
			cursor = last_z - min_spacing
		if cursor < start_z - seg_len + 4.0:
			break
		while absf(cursor - float(ctx.get("pad_z", -1e9))) < 4.5:
			cursor -= 2.0
		if cursor < start_z - seg_len + 4.0:
			break
		var type: String
		var x: float
		if mode == "character":
			type = CHARACTER_TYPES[rng.randi_range(0, CHARACTER_TYPES.size() - 1)]
			if feature == "slide_run" and i == 0:
				type = "slide"
			if feature == "platforms":
				type = "block" if i % 2 == 0 else "jump"
			# jump/slide barriers are centred near the lane; blocks sit
			# off-lane so a corridor always remains.
			x = lane + rng.randf_range(-0.8, 0.8) if type != "block" \
				else lane + (2.6 if rng.randf() < 0.5 else -2.6) + rng.randf_range(-0.4, 0.4)
		else:
			type = "block"
			# Slalom: alternate sides of the lane; never wall off the road.
			var side: float = 1.0 if i % 2 == 0 else -1.0
			if feature != "slalom":
				side = 1.0 if rng.randf() < 0.5 else -1.0
			x = lane + side * rng.randf_range(2.4, 3.6)
		x = clampf(x, -width / 2.0 + 1.4, width / 2.0 - 1.4)
		out.append({"type": type, "x": snappedf(x, 0.1), "z": snappedf(cursor, 0.1)})
		last_z = cursor
		cursor -= min_spacing + rng.randf_range(0.0, 5.0)
	ctx["last_obstacle_z"] = last_z
	return out
