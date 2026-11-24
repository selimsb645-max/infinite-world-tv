class_name ObstacleGenerator
extends RefCounted
## ObstacleGenerator - places obstacles inside one segment so the segment stays passable.
##
## The rule that matters: every z-band must keep at least one lane free, or be jumpable, or
## be slidable. Placement is therefore lane-aware, not random scatter.

const KIND_SIZES := {
	"barrier": Vector3(2.0, 1.2, 1.2),
	"crate": Vector3(1.8, 1.6, 1.8),
	"rock": Vector3(1.6, 1.4, 1.6),
	"ice_block": Vector3(1.9, 1.3, 1.9),
	"low_bar": Vector3(2.0, 0.5, 1.0),      # slide under
	"high_bar": Vector3(6.0, 0.6, 1.0),     # jump over (full width)
	"speed_gate": Vector3(6.0, 3.0, 0.6),   # vehicle only, passes over
}

func place(segment: Dictionary, kinds: Array, budget: int, min_gap: float,
		rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if kinds.is_empty() or budget <= 0:
		return out
	var length: float = segment["length"]
	var start_z: float = segment["start_z"]
	# keep 8 m clear at both ends so entries/exits are always safe
	var usable := length - 16.0
	if usable < 10.0:
		return out
	var slots := int(floor(usable / maxf(min_gap, 4.0)))
	slots = min(slots, budget)
	if slots <= 0:
		return out
	var step := usable / float(slots)
	var is_vehicle: bool = segment["mode"] == "vehicle"
	for i in slots:
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		if is_vehicle and kind in ["low_bar", "high_bar"]:
			kind = "barrier"
		var size: Vector3 = KIND_SIZES.get(kind, Vector3(2.0, 1.2, 1.2))
		var z := start_z - 8.0 - step * (float(i) + 0.5)
		var x := 0.0
		if size.x < GenerationConfig.TRACK_HALF_WIDTH * 1.5:
			var lanes: Array = GenerationConfig.LANE_X.duplicate()
			if rng.randf() < 0.35:
				lanes.erase(0.0)
			x = lanes[rng.randi_range(0, lanes.size() - 1)]
		var y := size.y * 0.5
		if kind == "high_bar":
			y = 1.4
		out.append({
			"kind": kind,
			"pos": Vector3(x, y, z),
			"size": size,
			"mode": segment["mode"],
			"segment_start": start_z,
		})
	return out
