class_name VideoRecoveryManager
extends RefCounted
## Phase 06 — bounded failure recovery for the video pipeline (NOT
## the Phase 04 gameplay RecoveryManager; that one unsticks the
## player, this one repairs recordings). Every issue gets at most
## max_attempts recovery actions inside a rolling budget window;
## when the window's budget is spent the answer is "give_up" and
## the renderer logs the segment as failed instead of looping.
## There is deliberately no timer and no self-calling code here,
## so an uncontrolled restart loop is impossible by construction.
##
## Phase 09 — budgets are WINDOWED, not lifetime. The original
## counters never reset, so in a weeks-long run three transient
## failures permanently disabled recovery for that issue class.
## Attempts now expire after budget_window_sec; only attempts
## inside the window count against max_attempts.

var max_attempts: int = 3
var budget_window_sec: float = 3600.0
var attempts: Dictionary = {}  # issue -> Array[int] msec timestamps
var actions_taken: Array[String] = []
## Test hook: when >= 0 this replaces the real clock, so tests can
## move time deterministically instead of waiting out the window.
var clock_override_msec: int = -1

func _now_msec() -> int:
	return clock_override_msec if clock_override_msec >= 0 \
		else Time.get_ticks_msec()

## Attempts for an issue that still fall inside the budget window.
## Prunes (and stores) the expired ones as a side effect.
func _recent(issue: String) -> Array:
	var cutoff := _now_msec() - int(budget_window_sec * 1000.0)
	var kept: Array = []
	for t in attempts.get(issue, []):
		if int(t) > cutoff:
			kept.append(int(t))
	attempts[issue] = kept
	return kept

func reset() -> void:
	attempts.clear()
	actions_taken.clear()

func can_attempt(issue: String) -> bool:
	return _recent(issue).size() < max_attempts

func exhausted(issue: String) -> bool:
	return not can_attempt(issue)

## The recovery action for an issue, or "give_up" when its window
## budget is spent. Calling this consumes one attempt.
func plan_action(issue: String) -> String:
	if not can_attempt(issue):
		return "give_up"
	var stamps := _recent(issue)
	stamps.append(_now_msec())
	attempts[issue] = stamps
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
