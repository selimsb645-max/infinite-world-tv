class_name VideoRecoveryManager
extends RefCounted
## Phase 06 — bounded failure recovery for the video pipeline (NOT
## the Phase 04 gameplay RecoveryManager; that one unsticks the
## player, this one repairs recordings). Every issue gets at most
## max_attempts recovery actions, counted explicitly; when the budget
## is spent the answer is "give_up" and the renderer logs the segment
## as failed instead of looping. There is deliberately no timer and
## no self-calling code here, so an uncontrolled restart loop is
## impossible by construction.

var max_attempts: int = 3
var attempts: Dictionary = {}  # issue -> count
var actions_taken: Array[String] = []

func reset() -> void:
	attempts.clear()
	actions_taken.clear()

func can_attempt(issue: String) -> bool:
	return int(attempts.get(issue, 0)) < max_attempts

func exhausted(issue: String) -> bool:
	return not can_attempt(issue)

## The recovery action for an issue, or "give_up" when its budget is
## spent. Calling this consumes one attempt.
func plan_action(issue: String) -> String:
	if not can_attempt(issue):
		return "give_up"
	attempts[issue] = int(attempts.get(issue, 0)) + 1
	var action := "none"
	match issue:
		"ENCODE_FAILURE":
			action = "reencode"
		"INVALID_OUTPUT":
			action = "reencode_fallback"  # re-encode at 720p config
		"ENCODER_OVERLOAD":
			action = "fallback_resolution"
		"AUDIO_LOSS", "AV_SYNC_DRIFT":
			action = "reencode_without_audio"
		"STORAGE_LOW":
			action = "cleanup_storage"
		"MISSING_FRAMES", "LOW_CAPTURE_FPS":
			action = "restart_capture"
		_:
			action = "none"
	actions_taken.append("%s:%s" % [issue, action])
	return action
