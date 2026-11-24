class_name SegmentGenerator
extends RefCounted
## Expands one route segment into concrete level content: obstacles
## (via ObstacleGenerator), collectibles along the route lane,
## platforms / moving platforms for character sections, speed gates,
## bridge rails and tunnel arches for vehicle sections, plus the
## ground/path strips the WorldManager builds. A "gap" segment omits
## part of its ground strip and spans the hole with a platform, sized
## by the difficulty profile (validator re-checks every limit).

var _obstacles := ObstacleGenerator.new()

## Returns a content dict with arrays: obstacles, collectibles,
## platforms, moving_platforms, gates, rails, tunnel_arches, gaps,
## ground_strips, path_strips.
func build_segment(rng: RandomNumberGenerator, segment: Dictionary,
		difficulty: Dictionary, ctx: Dictionary, width: float) -> Dictionary:
	var content: Dictionary = {
		"obstacles": [], "collectibles": [], "platforms": [], "moving_platforms": [],
		"gates": [], "rails": [], "tunnel_arches": [], "gaps": [],
		"ground_strips": [], "path_strips": [],
	}
	var mode: String = str(segment["mode"])
	var feature: String = str(segment["feature"])
	var lane: float = float(segment["lane_offset"])
	var start_z: float = float(segment["start_z"])
	var seg_len: float = float(segment["length"])
	var mid_z: float = start_z - seg_len / 2.0

	# Ground + path strips (gap segments split the ground around a hole).
	if feature == "gap" and mode == "character":
		var gap_len: float = snappedf(rng.randf_range(2.8, float(difficulty["max_gap"])), 0.1)
		var gap_z: float = mid_z
		content["gaps"].append({"z_center": gap_z, "len": gap_len})
		var near_len: float = start_z - (gap_z + gap_len / 2.0)
		var far_len: float = (gap_z - gap_len / 2.0) - (start_z - seg_len)
		content["ground_strips"].append({"z_center": start_z - near_len / 2.0, "len": near_len, "x": lane, "w": width + 30.0})
		content["ground_strips"].append({"z_center": (gap_z - gap_len / 2.0) - far_len / 2.0, "len": far_len, "x": lane, "w": width + 30.0})
		# Platform spanning the gap (validator requires this).
		content["platforms"].append({"x": lane, "y": 0.55, "z": gap_z,
			"w": 3.2, "d": gap_len + 2.4})
	else:
		var strip_w: float = width if feature == "bridge" else width + 30.0
		content["ground_strips"].append({"z_center": mid_z, "len": seg_len, "x": lane, "w": strip_w})
	content["path_strips"].append({"z_center": mid_z, "len": seg_len, "x": lane, "w": width})

	# Obstacles.
	content["obstacles"] = _obstacles.obstacles_for_segment(rng, segment, difficulty, ctx, width)

	# Feature-specific structures.
	match feature:
		"platforms":
			var steps: int = rng.randi_range(2, 3)
			var step_max: float = float(difficulty["max_platform_step"])
			var y: float = 0.0
			for s in steps:
				y = minf(y + rng.randf_range(0.5, step_max), 1.3)
				content["platforms"].append({
					"x": lane + rng.randf_range(-1.5, 1.5), "y": snappedf(y, 0.05),
					"z": start_z - seg_len * float(s + 1) / float(steps + 1),
					"w": 3.4, "d": 3.4})
			if rng.randf() < 0.6:
				content["moving_platforms"].append({
					"x": lane, "y": 0.8, "z": mid_z, "w": 3.0, "d": 3.0,
					"range": 1.2, "speed": rng.randf_range(0.6, 1.0)})
		"gates":
			var gate_count: int = rng.randi_range(2, 3)
			for g in gate_count:
				content["gates"].append({"x": lane,
					"z": start_z - seg_len * float(g + 1) / float(gate_count + 1)})
		"bridge":
			for side in [-1.0, 1.0]:
				content["rails"].append({"x": lane + side * (width / 2.0 - 0.3),
					"z_center": mid_z, "len": seg_len})
		"tunnel":
			var arch_count: int = int(seg_len / 8.0)
			for a in arch_count:
				content["tunnel_arches"].append(start_z - 4.0 - float(a) * 8.0)

	# Collectibles trail the route lane, clear of obstacles (validator
	# re-checks clearance; generation keeps a margin).
	var trail: int = rng.randi_range(3, 5)
	for c in trail:
		var cz: float = start_z - seg_len * float(c + 1) / float(trail + 1)
		var cx: float = lane + rng.randf_range(-1.2, 1.2)
		var clear: bool = true
		for ob in content["obstacles"]:
			if absf(float(ob["x"]) - cx) < 2.2 and absf(float(ob["z"]) - cz) < 2.2:
				clear = false
		if clear:
			(content["collectibles"] as Array).append(Vector3(snappedf(cx, 0.1), 1.0, snappedf(cz, 0.1)))
	return content
