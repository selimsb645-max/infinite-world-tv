class_name CaptureHealthMonitor
extends RefCounted
## Phase 06 — turns raw pipeline stats into a health verdict with
## named issue codes, so VideoRecoveryManager can act on causes
## instead of symptoms. Pure evaluation, no side effects: feed it the
## stats dictionary VideoRenderer assembles after each segment.
##
## Stats keys (all optional, sensible defaults):
##   recording_sec, target_fps, capture_fps, frames_expected,
##   frames_captured, encode_exit_code, encode_fps, output_valid,
##   audio_expected, audio_present, av_sync_offset, storage_ok
##
## Issue codes: MISSING_FRAMES, LOW_CAPTURE_FPS, ENCODE_FAILURE,
## ENCODER_OVERLOAD, INVALID_OUTPUT, AUDIO_LOSS, AV_SYNC_DRIFT,
## STORAGE_LOW.

const MISSING_FRAME_RATIO := 0.25
const LOW_FPS_RATIO := 0.6
const MAX_SYNC_OFFSET_SEC := 0.5
const MIN_EVAL_SEC := 2.0

func evaluate(stats: Dictionary) -> Dictionary:
	var issues: Array[String] = []
	var recording_sec := float(stats.get("recording_sec", 0.0))
	var expected := int(stats.get("frames_expected", 0))
	var captured := int(stats.get("frames_captured", 0))
	if expected > 0 and recording_sec >= MIN_EVAL_SEC:
		var missing_ratio := 1.0 - clampf(float(captured) / float(expected), 0.0, 1.0)
		if missing_ratio > MISSING_FRAME_RATIO:
			issues.append("MISSING_FRAMES")
	var target_fps := float(stats.get("target_fps", 0.0))
	var capture_fps := float(stats.get("capture_fps", 0.0))
	if target_fps > 0.0 and recording_sec >= MIN_EVAL_SEC \
			and capture_fps < target_fps * LOW_FPS_RATIO:
		issues.append("LOW_CAPTURE_FPS")
	if int(stats.get("encode_exit_code", 0)) != 0:
		issues.append("ENCODE_FAILURE")
	var encode_fps := float(stats.get("encode_fps", 0.0))
	if target_fps > 0.0 and encode_fps > 0.0 and encode_fps < target_fps * 0.5:
		issues.append("ENCODER_OVERLOAD")
	if stats.has("output_valid") and not bool(stats["output_valid"]):
		if not issues.has("ENCODE_FAILURE"):
			issues.append("INVALID_OUTPUT")
	if bool(stats.get("audio_expected", false)) \
			and not bool(stats.get("audio_present", true)):
		issues.append("AUDIO_LOSS")
	if absf(float(stats.get("av_sync_offset", 0.0))) > MAX_SYNC_OFFSET_SEC:
		issues.append("AV_SYNC_DRIFT")
	if stats.has("storage_ok") and not bool(stats["storage_ok"]):
		issues.append("STORAGE_LOW")
	return {"healthy": issues.is_empty(), "issues": issues}
