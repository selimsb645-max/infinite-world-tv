class_name RouteGenerator
extends RefCounted
## RouteGenerator - decides the sequence of segments that makes up one level.
##
## Two rules keep it playable: a level always opens with a character run and closes with a
## character run, and it always contains at least one vehicle section once difficulty allows.
## Mode switches are therefore never at the very start or the very finish.

func build(world: Dictionary, difficulty: float, target_length: float,
		rng: RandomNumberGenerator, seg_gen: SegmentGenerator) -> Array:
	var segments: Array = []
	var z := 0.0
	var guard := 0
	# opener: a clean run so the player is never thrown straight into an obstacle
	segments.append(seg_gen.build("run", z, difficulty * 0.5, rng))
	z = segments[0]["end_z"]
	var vehicle_used := false
	var last_type := "run"
	while absf(z) < target_length and guard < 24:
		guard += 1
		var type: String = _pick(world, difficulty, rng, last_type, vehicle_used, guard)
		if SegmentGenerator.is_vehicle_type(type):
			vehicle_used = true
		var seg := seg_gen.build(type, z, difficulty, rng)
		segments.append(seg)
		z = seg["end_z"]
		last_type = type
	# closer: a run with no obstacles so the finish line is always reachable
	segments.append(seg_gen.build("run", z, 0.0, rng))
	return segments

func _pick(world: Dictionary, difficulty: float, rng: RandomNumberGenerator,
		last_type: String, vehicle_used: bool, step: int) -> String:
	# force a vehicle section early enough that every level has both modes
	if not vehicle_used and step >= 2:
		return "road"
	var type: String = _weighted(world, difficulty, rng)
	# never repeat the same type twice in a row: that is what makes levels feel copied
	if type == last_type:
		type = _weighted(world, difficulty, rng)
	return type

func _weighted(world: Dictionary, difficulty: float, rng: RandomNumberGenerator) -> String:
	var table: Dictionary = world.get("segments", {})
	var total := 0.0
	var weighted: Array = []
	for key in table.keys():
		var w := float(table[key])
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
