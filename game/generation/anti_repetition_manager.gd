class_name AntiRepetitionManager
extends RefCounted
## AntiRepetitionManager - the guard that stops "same level, new paint".
##
## Three separate checks, in increasing cost: exact fingerprint, recent-world exclusion and
## structural similarity. Only the last one is expensive, so it runs last and only against
## the recent window.

var history: LevelHistoryManager
var fingerprint_manager: LevelFingerprintManager

func _init() -> void:
	history = LevelHistoryManager.new()
	fingerprint_manager = LevelFingerprintManager.new()

func reset() -> void:
	history.clear()

## Returns "" when the level is acceptable, otherwise a reason string for the log.
func rejection_reason(spec: Dictionary) -> String:
	var fp := fingerprint_manager.fingerprint(spec)
	if history.has_fingerprint(fp):
		return "duplicate_fingerprint"
	var world: String = spec.get("theme", "")
	var recent := history.recent_worlds(1)
	if not recent.is_empty() and recent[0] == world:
		return "same_world_as_previous"
	var features := fingerprint_manager.structural(spec)
	var window := history.recent_features(GenerationConfig.RECENT_EXCLUSION)
	for past in window:
		if fingerprint_manager.similarity(features, past) >= GenerationConfig.SIMILARITY_LIMIT:
			return "structural_clone"
	return ""

func accept(spec: Dictionary) -> void:
	history.record(
		fingerprint_manager.fingerprint(spec),
		fingerprint_manager.structural(spec),
		String(spec.get("theme", ""))
	)

func reject() -> void:
	history.count_rejection()

func stats() -> Dictionary:
	return {
		"generated": history.total_generated(),
		"rejections": history.rejections(),
		"window": history.size(),
	}
