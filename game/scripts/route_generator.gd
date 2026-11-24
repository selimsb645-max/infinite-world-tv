class_name RouteGenerator
extends RefCounted
## Plans the route of a generated level: an ordered list of segments,
## each either a character section or a vehicle section, with a feature
## (run / platforms / gap / slalom / gates / bridge / tunnel / curve)
## and a gentle lane offset. Offsets change by at most the configured
## lane shift per segment, so the road the player follows is always
## continuous. A transition segment joins the two modes; the vehicle
## pad (mode-switch point) is placed inside it.

const CHARACTER_FEATURES: Array[String] = ["run", "run", "platforms", "slide_run", "gap"]
const VEHICLE_FEATURES: Array[String] = ["slalom", "gates", "curve", "bridge", "tunnel"]

var _config: GenerationConfig

func _init(config: GenerationConfig = null) -> void:
	_config = config if config != null else GenerationConfig.new()

## Returns {segments, start_mode, vehicle_pad_z, total_length}.
## Segment z ranges: segment i occupies [start_z - length, start_z],
## starting just past the spawn safe zone.
func plan(rng: RandomNumberGenerator, difficulty: Dictionary, segment_count: int,
		force_mixed: bool = true) -> Dictionary:
	var segments: Array[Dictionary] = []
	var mode: String = "character" if rng.randf() < 0.5 else "vehicle"
	var start_mode: String = mode
	var lane: float = 0.0
	var z: float = -_config.spawn_safe_distance - 2.0
	var pad_z: float = -30.0
	var has_both: bool = false
	for i in segment_count:
		# Switch modes at least once in mixed routes, at a random point.
		if force_mixed and i == segment_count / 2:
			mode = "vehicle" if mode == "character" else "character"
		var feature: String
		if mode == "character":
			feature = CHARACTER_FEATURES[rng.randi_range(0, CHARACTER_FEATURES.size() - 1)]
		else:
			feature = VEHICLE_FEATURES[rng.randi_range(0, VEHICLE_FEATURES.size() - 1)]
		var seg_len: float = rng.randf_range(_config.segment_length_min, _config.segment_length_max)
		lane = clampf(lane + rng.randf_range(-_config.max_lane_shift, _config.max_lane_shift), -2.0, 2.0)
		var is_transition: bool = i > 0 and str(segments[i - 1]["mode"]) != mode
		if is_transition:
			has_both = true
			pad_z = z - 3.0
		segments.append({
			"index": i, "mode": mode, "feature": feature,
			"length": seg_len, "start_z": z, "lane_offset": lane,
			"transition": is_transition,
		})
		z -= seg_len
	if not has_both and force_mixed and segment_count >= 2:
		# Guarantee the pad sits somewhere sensible even if the mode
		# switch landed on the final segment boundary.
		pad_z = segments[segment_count / 2]["start_z"] - 3.0
		has_both = true
	var total_length: float = -z + _config.finish_safe_distance + 8.0
	return {"segments": segments, "start_mode": start_mode,
		"vehicle_pad_z": pad_z, "total_length": total_length, "mixed": has_both}
