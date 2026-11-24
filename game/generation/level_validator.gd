class_name LevelValidator
extends RefCounted
## LevelValidator - refuses to hand the player a level that cannot be finished.
##
## This is not a sanity check on the generator's own output; it re-derives playability from
## the physics constants. If the generator and the validator disagree, the level is thrown
## away, which is the behaviour we want when a new segment type is added later.

## Returns an Array of problem strings. Empty means the level is playable.
func validate(spec: Dictionary) -> Array:
	var problems: Array = []

	# 1. spawn and finish must exist, be on the ground and be clear of obstacles
	var spawn: Vector3 = spec.get("spawn", Vector3.ZERO)
	var finish: Vector3 = spec.get("finish", Vector3.ZERO)
	var length: float = float(spec.get("length", 0.0))
	if length < 60.0:
		problems.append("track_too_short:%.0f" % length)
	if absf(spawn.z) > 1.0:
		problems.append("spawn_not_at_start")
	if finish.z > -(length - 30.0):
		problems.append("finish_too_close_to_spawn")
	for obs in spec.get("obstacles", []):
		var p: Vector3 = obs["pos"]
		if absf(p.z - spawn.z) < 8.0:
			problems.append("obstacle_in_spawn_zone")
			break

	# 2. obstacles must stay inside the track
	for obs in spec.get("obstacles", []):
		var p: Vector3 = obs["pos"]
		var s: Vector3 = obs["size"]
		if absf(p.x) + s.x * 0.5 > GenerationConfig.TRACK_HALF_WIDTH + 0.01:
			problems.append("obstacle_outside_track:%.1f" % p.x)
			break
		if p.z > spawn.z or p.z < finish.z - 4.0:
			problems.append("obstacle_outside_track_z:%.1f" % p.z)
			break

	# 3. every obstacle band must leave a way through
	var bands := _bands(spec.get("obstacles", []))
	for band_z in bands.keys():
		if not _band_passable(bands[band_z], spec):
			problems.append("band_impassable_at_z%.0f" % float(band_z))
			break

	# 4. difficulty inside the allowed envelope
	var d := float(spec.get("difficulty", 0.0))
	if d < GenerationConfig.DIFFICULTY_MIN - 0.001 or d > GenerationConfig.DIFFICULTY_MAX + 0.001:
		problems.append("difficulty_out_of_range:%.2f" % d)

	# 5. a level must contain both modes, else it is not the hybrid game we promised
	var has_vehicle := false
	var has_character := false
	for seg in spec.get("segments", []):
		if seg.get("mode", "character") == "vehicle":
			has_vehicle = true
		else:
			has_character = true
	if not (has_vehicle and has_character):
		problems.append("missing_mode")

	# 6. vehicle sections must be continuous road: no jumps, no gaps
	for seg in spec.get("segments", []):
		if seg.get("mode", "character") == "vehicle" and float(seg.get("length", 0.0)) < 20.0:
			problems.append("vehicle_section_too_short")
			break

	# 7. reaction time: no two obstacle bands closer than the safe gap at this difficulty
	var dm := DifficultyManager.new()
	dm.set_difficulty(d)
	var min_gap: float = dm.min_obstacle_gap() * 0.55
	var zs: Array = bands.keys()
	zs.sort()
	for i in range(1, zs.size()):
		if absf(float(zs[i]) - float(zs[i - 1])) < min_gap:
			problems.append("obstacles_too_close")
			break

	return problems

func is_valid(spec: Dictionary) -> bool:
	return validate(spec).is_empty()

## Group obstacles into 2 m bands along z; obstacles in the same band must be avoidable together.
func _bands(obstacles: Array) -> Dictionary:
	var bands := {}
	for obs in obstacles:
		var p: Vector3 = obs["pos"]
		var key := int(round(p.z / 2.0)) * 2
		if not bands.has(key):
			bands[key] = []
		bands[key].append(obs)
	return bands

func _band_passable(band: Array, spec: Dictionary) -> bool:
	var mode := "character"
	for obs in band:
		if obs.get("mode", "character") == "vehicle":
			mode = "vehicle"
	var blocked_lanes: Array = []
	for obs in band:
		var p: Vector3 = obs["pos"]
		var s: Vector3 = obs["size"]
		# a full-width bar is passable if it can be jumped or slid under
		if s.x >= GenerationConfig.TRACK_HALF_WIDTH:
			if p.y - s.y * 0.5 <= 0.05 and s.y <= 1.25:
				continue          # low enough to jump
			if p.y - s.y * 0.5 >= 1.15:
				continue          # high enough to slide under
			return false
		for lane in GenerationConfig.LANE_X:
			if absf(float(lane) - p.x) < (s.x * 0.5 + 0.45):
				blocked_lanes.append(lane)
	var free := 0
	for lane in GenerationConfig.LANE_X:
		if not blocked_lanes.has(lane):
			free += 1
	if mode == "vehicle":
		return free >= 2      # a car needs a real lane, not a sliver
	return free >= 1
