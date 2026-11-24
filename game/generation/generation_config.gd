class_name GenerationConfig
extends RefCounted
## GenerationConfig - every tunable in one place.
##
## Why a class and not a .tres resource: the generator runs in headless tests thousands of
## times and must be identical on every machine. Constants here are the contract; nothing
## else in generation/ hard-codes a number.

# --- physics the validator must agree with (Phase 02 controllers) ---
const RUN_SPEED := 9.0
const GRAVITY := 26.0
const JUMP_VELOCITY := 9.2
const VEHICLE_MAX_SPEED := 26.0

# jump arc: airtime = 2*v/g, reach = speed * airtime
const AIRTIME := 2.0 * JUMP_VELOCITY / GRAVITY
const JUMP_REACH := RUN_SPEED * AIRTIME
const SAFE_GAP := JUMP_REACH * 0.62

# --- track ---
const LANE_X := [-2.4, -1.2, 0.0, 1.2, 2.4]
const TRACK_HALF_WIDTH := 6.0
const SPAWN_Z := 0.0

# --- difficulty ---
const DIFFICULTY_MIN := 0.05
const DIFFICULTY_MAX := 0.95
const DIFFICULTY_PER_LEVEL := 0.035
const MAX_OBSTACLES := 26
const MIN_OBSTACLE_GAP_EASY := 22.0
const MIN_OBSTACLE_GAP_HARD := 9.0

# --- anti-repetition ---
const HISTORY_SIZE := 500
const RECENT_EXCLUSION := 20
const SIMILARITY_LIMIT := 0.975   # calibrated 2026-11-24: different levels sit at p90=0.908, p99=0.990
const MAX_GENERATION_ATTEMPTS := 8

# --- streaming ---
const SEGMENTS_AHEAD := 2
const SEGMENTS_KEPT := 3
