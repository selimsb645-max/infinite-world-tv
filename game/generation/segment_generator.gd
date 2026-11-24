class_name SegmentGenerator
extends RefCounted
## SegmentGenerator - turns a segment type into a concrete slice of track.
##
## A segment is data only: where it starts, how long it is, which mode it is played in and
## what sits on it. The world builder reads the merged result, so a new segment type never
## touches rendering code.

const SEGMENT_LENGTHS := {
	"run": [30.0, 46.0], "jump": [24.0, 38.0], "slide": [22.0, 34.0],
	"road": [46.0, 80.0], "curve": [40.0, 64.0], "tunnel": [36.0, 56.0],
	"bridge": [30.0, 50.0],
}

const VEHICLE_TYPES := ["road", "curve", "tunnel", "bridge"]

static func is_vehicle_type(type: String) -> bool:
	return type in VEHICLE_TYPES

func build(type: String, start_z: float, difficulty: float, rng: RandomNumberGenerator) -> Dictionary:
	var bounds: Array = SEGMENT_LENGTHS.get(type, [28.0, 40.0])
	var base_len := rng.randf_range(bounds[0], bounds[1])
	# hard levels get slightly shorter reaction windows, never shorter than 18 m
	var length := maxf(18.0, base_len * lerpf(1.0, 0.86, difficulty))
	return {
		"type": type,
		"mode": "vehicle" if is_vehicle_type(type) else "character",
		"start_z": start_z,
		"length": length,
		"end_z": start_z - length,
		"difficulty": difficulty,
		"safe_entry": true,
		"safe_exit": true,
	}
