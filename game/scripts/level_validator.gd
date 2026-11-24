class_name LevelValidator
extends RefCounted
## Validates a generated level dictionary BEFORE it is shown to the
## player. Pure data checks (no scene needed), using the traversal
## limits in GenerationConfig, which are derived conservatively from
## the real Phase 02 controller physics.
##
## Checks: spawn/finish safety, obstacle bounds and spacing, jump
## distances (ground gaps), platform step heights, vehicle road
## connectivity (ground-strip continuity + lane shifts + a guaranteed
## driveable corridor beside every block), mode-transition pad safety,
## collectible clearance, and difficulty-profile constraints.

var _config: GenerationConfig

func _init(config: GenerationConfig = null) -> void:
	_config = config if config != null else GenerationConfig.new()

## Returns {valid: bool, errors: Array[String]}.
func validate(level: Dictionary, difficulty: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var length: float = float(level.get("length", 0.0))
	var width: float = float(level.get("width", 0.0))
	if length < 40.0:
		errors.append("level_too_short")
	if width < 10.0:
		errors.append("level_too_narrow")
	var obstacles: Array = level.get("obstacles", [])
	var finish_z: float = -length + 2.0

	# --- Spawn / finish safety -------------------------------------
	for ob in obstacles:
		var z: float = float(ob.get("z", 0.0))
		if z > -_config.spawn_safe_distance:
			errors.append("obstacle_in_spawn_zone@%.1f" % z)
		if z < finish_z + _config.finish_safe_distance:
			errors.append("obstacle_in_finish_zone@%.1f" % z)
		# --- Bounds -------------------------------------------------
		var x: float = float(ob.get("x", 0.0))
		var half_span: float = 3.0 if str(ob.get("type", "")) in ["jump", "slide"] else 1.1
		if absf(x) + half_span > width / 2.0 + 3.0:
			errors.append("obstacle_out_of_bounds@%.1f,%.1f" % [x, z])

	# --- Obstacle spacing -------------------------------------------
	var sorted: Array = obstacles.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["z"]) > float(b["z"]))
	for i in range(sorted.size() - 1):
		var a: Dictionary = sorted[i]
		var b: Dictionary = sorted[i + 1]
		var dz: float = absf(float(a["z"]) - float(b["z"]))
		var dx: float = absf(float(a["x"]) - float(b["x"]))
		# Obstacles in overlapping lanes need full reaction spacing;
		# far-apart lanes may sit a little closer in z.
		var needed: float = float(difficulty.get("min_spacing", 7.0)) if dx < 3.0 \
			else float(difficulty.get("min_spacing", 7.0)) * 0.55
		if dz < needed:
			errors.append("obstacles_too_close@%.1f/%.1f dz=%.2f need=%.2f" % [float(a["z"]), float(b["z"]), dz, needed])

	# --- Vehicle corridor: every block must leave a driveable gap ---
	for ob in obstacles:
		if str(ob.get("type", "")) == "block":
			var x: float = float(ob.get("x", 0.0))
			var left_free: float = (x - 1.1) - (-width / 2.0)
			var right_free: float = (width / 2.0) - (x + 1.1)
			if left_free < _config.vehicle_min_corridor and right_free < _config.vehicle_min_corridor:
				errors.append("vehicle_corridor_blocked@%.1f" % x)

	# --- Ground gaps (character jump distance) ----------------------
	var gaps: Array = level.get("gaps", [])
	var platforms: Array = level.get("platforms", [])
	for gap in gaps:
		var glen: float = float(gap.get("len", 0.0))
		if glen > _config.max_jump_distance:
			errors.append("gap_too_long len=%.2f" % glen)
		if glen > float(difficulty.get("max_gap", 4.4)) + 0.01:
			errors.append("gap_exceeds_difficulty len=%.2f" % glen)
		# A platform must span the gap so the route across exists.
		var gz: float = float(gap.get("z_center", 0.0))
		var spanned: bool = false
		for p in platforms:
			var pz: float = float(p.get("z", 0.0))
			var pd: float = float(p.get("d", 0.0))
			if pz - pd / 2.0 <= gz + glen / 2.0 + 0.5 and pz + pd / 2.0 >= gz - glen / 2.0 - 0.5:
				spanned = true
		if not spanned:
			errors.append("gap_not_spanned@%.1f" % gz)

	# --- Platform step heights ---------------------------------------
	var plats: Array = platforms.duplicate()
	plats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["z"]) > float(b["z"]))
	var prev_top: float = 0.0
	for p in plats:
		var top: float = float(p.get("y", 0.0))
		if top > _config.max_jump_height:
			errors.append("platform_too_high y=%.2f" % top)
		if top - prev_top > _config.max_platform_step:
			errors.append("platform_step_too_big %.2f->%.2f" % [prev_top, top])
		prev_top = top
	for mp in level.get("moving_platforms", []):
		if float(mp.get("y", 0.0)) > _config.max_jump_height:
			errors.append("moving_platform_too_high")

	# --- Road connectivity: ground strips + lane shifts ---------------
	var strips: Array = level.get("ground_strips", [])
	if not strips.is_empty():
		var ss: Array = strips.duplicate()
		ss.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["z_center"]) + float(a["len"]) / 2.0 > float(b["z_center"]) + float(b["len"]) / 2.0)
		# Coverage walk from the spawn apron (z=+10) to the finish zone:
		# any hole must be a declared, platform-spanned gap.
		var cursor: float = 10.0
		for s in ss:
			var near: float = float(s["z_center"]) + float(s["len"]) / 2.0
			var far: float = float(s["z_center"]) - float(s["len"]) / 2.0
			if near < cursor - 0.6:
				var hole_center: float = (cursor + near) / 2.0
				var declared: bool = false
				for gap in gaps:
					if absf(float(gap.get("z_center", 0.0)) - hole_center) < 2.0:
						declared = true
				if not declared:
					errors.append("road_discontinuity@%.1f hole=%.2f" % [cursor, cursor - near])
			cursor = minf(cursor, far)
		if cursor > finish_z + 1.0:
			errors.append("road_ends_before_finish cursor=%.1f" % cursor)
		for i in range(ss.size() - 1):
			if absf(float(ss[i].get("x", 0.0)) - float(ss[i + 1].get("x", 0.0))) > _config.max_lane_shift + 2.5:
				errors.append("road_lane_jump@%.1f" % float(ss[i]["z_center"]))
	var segments: Array = level.get("segments", [])
	for i in range(segments.size() - 1):
		var d: float = absf(float(segments[i].get("lane_offset", 0.0)) - float(segments[i + 1].get("lane_offset", 0.0)))
		if d > _config.max_lane_shift:
			errors.append("segment_lane_shift_too_big %.2f" % d)

	# --- Mode transition pad ------------------------------------------
	var pad_z: float = float(level.get("vehicle_pad_z", 0.0))
	if pad_z > -4.0 or pad_z < finish_z + 4.0:
		errors.append("pad_out_of_range")
	for ob in obstacles:
		if absf(float(ob.get("z", 0.0)) - pad_z) < 3.5 and absf(float(ob.get("x", 0.0)) - 4.5) < 4.0:
			errors.append("pad_blocked_by_obstacle")

	# --- Collectibles ---------------------------------------------------
	for c in level.get("collectibles", []):
		var pos: Vector3 = c
		if absf(pos.x) > width / 2.0:
			errors.append("collectible_out_of_bounds")
		for ob in obstacles:
			if absf(float(ob.get("x", 0.0)) - pos.x) < _config.min_collectible_clearance \
					and absf(float(ob.get("z", 0.0)) - pos.z) < _config.min_collectible_clearance:
				errors.append("collectible_inside_obstacle")
				break

	# --- Difficulty constraints ------------------------------------------
	var density: float = float(obstacles.size()) / maxf(length, 1.0) * 10.0
	var max_density: float = float(difficulty.get("obstacles_per_segment", 5)) / 2.2
	if density > max_density:
		errors.append("density_exceeds_difficulty %.2f>%.2f" % [density, max_density])
	if segments.is_empty():
		errors.append("no_segments")

	return {"valid": errors.is_empty(), "errors": errors}
