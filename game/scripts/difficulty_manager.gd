class_name DifficultyManager
extends RefCounted
## Produces a difficulty profile for a level number. Difficulty rises
## gradually over the first ~40 levels and then plateaus at a hard cap
## (configurable via max_difficulty), so late levels are challenging but
## never impossible: every value stays inside the traversal limits the
## LevelValidator enforces (spacing never below the reaction floor,
## gaps never above the conservative jump distance).
##
## An optional performance dictionary can nudge difficulty slightly
## (e.g. repeated deaths ease the next level a little); the nudge is
## bounded to +/-0.05 so it can never break the caps.

var max_difficulty: float = 1.0
var ramp_levels: int = 40  # levels over which difficulty reaches the cap

func profile_for(level_number: int, performance: Dictionary = {}) -> Dictionary:
	var t: float = clampf(float(maxi(level_number, 1) - 1) / float(ramp_levels), 0.0, 1.0)
	t = clampf(t * max_difficulty, 0.0, 1.0)
	# Bounded performance nudge: struggling players get a slightly
	# easier next level, flawless runs a slightly harder one.
	if performance.has("deaths"):
		var deaths: int = int(performance["deaths"])
		if deaths >= 3:
			t = clampf(t - 0.05, 0.0, 1.0)
	if performance.has("flawless") and bool(performance["flawless"]):
		t = clampf(t + 0.03, 0.0, 1.0)
	return {
		"index": t,
		"level_number": level_number,
		# Obstacles per segment grows 2 -> 5.
		"obstacles_per_segment": int(round(lerpf(2.0, 5.0, t))),
		# Spacing between obstacles shrinks 11 m -> 7 m (reaction floor:
		# at run speed 8 m/s, 7 m still gives ~0.85 s to react).
		"min_spacing": lerpf(11.0, 7.0, t),
		# Ground gaps grow 3.0 m -> 4.4 m, always < max_jump_distance 5.0.
		"max_gap": lerpf(3.0, 4.4, t),
		# Platform steps grow but stay under the validator's 1.35 m cap.
		"max_platform_step": lerpf(0.9, 1.3, t),
		# Longer levels as difficulty rises.
		"segment_count_bonus": int(floor(t * 3.0)),
	}
