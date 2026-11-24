class_name GenerationConfig
extends RefCounted
## Tunable limits for the Phase 03 procedural generation engine.
## Everything the generator / validator / anti-repetition system treats
## as a policy knob lives here, so difficulty and repetition behaviour
## can be rebalanced without touching generator code.
##
## Physics-derived constants come from the Phase 02 controllers:
## CharacterController JUMP_VELOCITY 9.5, GRAVITY 26.0, RUN_SPEED 8.0
##   -> jump apex = 9.5^2 / (2*26) ~= 1.74 m, air time ~= 0.73 s,
##      theoretical jump distance ~= 5.85 m. We validate against
##      conservative values below so generated levels stay fair.
## VehicleController body width is 1.9 m.

# --- Anti-repetition ---------------------------------------------------
var similarity_threshold: float = 0.80  # >= this vs recent history -> regenerate
var max_retries: int = 8                # bounded retries before fallback template
var history_size: int = 250             # bounded LevelHistoryManager capacity
var recent_window: int = 60             # entries structural similarity is checked against

# --- Level shape ---------------------------------------------------------
var min_segments_per_level: int = 4
var max_segments_per_level: int = 9
var segment_length_min: float = 22.0
var segment_length_max: float = 34.0
var spawn_safe_distance: float = 9.0    # no obstacles this close to spawn (z > -9)
var finish_safe_distance: float = 6.0   # clear run-out before the finish zone
var decor_per_level: int = 26

# --- Traversal limits (validator) ---------------------------------------
var max_jump_distance: float = 5.0      # conservative vs 5.85 m theoretical
var max_jump_height: float = 1.5        # conservative vs 1.74 m theoretical apex
var max_platform_step: float = 1.35     # max height gain between chained platforms
var max_lane_shift: float = 2.2         # max lateral route change per segment
var vehicle_min_corridor: float = 2.3   # free width a vehicle needs beside a block
var min_collectible_clearance: float = 1.6  # collectible vs obstacle centre distance

# --- Performance ----------------------------------------------------------
var pool_cap_per_key: int = 48          # ObjectPool cap per node kind

func to_dict() -> Dictionary:
	return {
		"similarity_threshold": similarity_threshold,
		"max_retries": max_retries,
		"history_size": history_size,
		"recent_window": recent_window,
		"max_jump_distance": max_jump_distance,
		"max_jump_height": max_jump_height,
	}
