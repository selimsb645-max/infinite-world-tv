# Phase 06 — Automated Video Production & Rendering Engine

Status: **built and tested locally** (2026-11-24). Video suite **84/84
PASS** (`tests/video_output.txt`: 71 headless logic checks + 13
real-pixel capture checks, `VIDEO_DONE failures=0`). Regressions
clean: Phase 02 smoke 26/26, Phase 03 generation 45/45, Phase 04
autopilot 29/29, Phase 05 asset 237/237.

**No live broadcasting was started.** Streaming (YouTube Live /
RTMP) is a later phase: this phase builds and unit-tests the RTMP
command and keeps it disabled by default.

## What was built

| Module | File | Responsibility |
|---|---|---|
| EncodingConfig | `game/scripts/encoding_config.gd` | Every pipeline knob: resolution (1080p/720p presets), fps (24/30/60), bitrates, x264 preset, segment duration, storage caps, retention, audio mix levels, ffmpeg paths, RTMP settings (disabled by default). `fallback()` = the safe 720p30 variant |
| GameCaptureManager | `game/scripts/game_capture_manager.gd` | Viewport frame capture after `frame_post_draw` at the configured rate, scaled to the configured resolution, written as a PNG sequence. Drop-aware scheduling: missed slots are counted, never burst-caught-up |
| FFmpegManager | `game/scripts/ffmpeg_manager.gd` | Single gateway to ffmpeg/ffprobe: encode-command building (H.264 + AAC, yuv420p, faststart, pinned duration), RTMP/FLV command building (not executed), process runs with timing, ffprobe validation (codec, resolution, fps, duration, A/V sync offset) |
| AudioMixer | `game/scripts/audio_mixer.gd` | Segment audio from Phase 05's original WAVs: music loop + current world's ambience loop + timestamped SFX events (collect/finish/switch, fed by GameManager hooks). Per-layer configurable gains, everything trimmed/padded to the exact segment duration, `dynaudnorm` + limiter against clipping. Missing clips are skipped and reported; an empty plan renders silence so the MP4 still has a valid AAC track |
| CameraCaptureController | `game/scripts/camera_capture_controller.gd` | Broadcast framing over the Phase 02 rig: dynamic distance (pulls back smoothly with speed; one additive `distance_scale` on CameraController, default 1.0 = original framing), world/mode tracking, horizon-stability and frustum-visibility checks |
| BroadcastOverlayManager | `game/scripts/broadcast_overlay_manager.gd` | Original overlay graphics on a CanvasLayer (so captures include them): world, level, score, mode, thin progress bar, optional channel branding. Edge panels, translucent, gameplay unobstructed |
| VideoSegmentManager | `game/scripts/video_segment_manager.gd` | Timestamped segment names; encode-to-`.partial.mp4` then rename only after ffprobe validation (safe finalization); interrupted-partial recovery on startup (valid → promoted, invalid → discarded, all reported) |
| StorageManager | `game/scripts/storage_manager.gd` | Usage accounting + enforcement: retention expiry, total-size cap, segment-count cap, oldest-first, never deletes the protected newest segment. Disk usage cannot grow unbounded |
| CaptureHealthMonitor | `game/scripts/capture_health_monitor.gd` | Stats → named issues: MISSING_FRAMES, LOW_CAPTURE_FPS, ENCODE_FAILURE, ENCODER_OVERLOAD, INVALID_OUTPUT, AUDIO_LOSS, AV_SYNC_DRIFT, STORAGE_LOW |
| VideoRecoveryManager | `game/scripts/video_recovery_manager.gd` | Bounded recovery per issue (max 3 attempts, then `give_up`): re-encode, 720p fallback re-encode, video-only re-encode, storage cleanup, capture-session restart at the next segment. No timers, no self-calls — an uncontrolled loop is impossible by construction. (Distinct from Phase 04's gameplay RecoveryManager) |
| VideoRenderer | `game/scripts/video_renderer.gd` | Orchestrator: capture → mix → encode → validate → finalize → storage enforcement → health + recovery loop; continuous mode with automatic segment rollover; live perf snapshot (game/capture/encode FPS, process time, RAM; GPU reported unavailable where there is none) |

Integration is opt-in, mirroring Phase 04: `game.setup_broadcast(cfg)`
creates the renderer; GameManager forwards HUD values to the overlay,
level progress in `_process`, and SFX events (collect / finish /
mode switch) to the mixer. With no `setup_broadcast()` call the game
behaves exactly as before — all four regression suites pass
unchanged.

## Measured on this VM (Xvfb + llvmpipe, no GPU) — real numbers

From `tests/video_output.txt` (run 2026-11-24):

- **720p run** (6 s of autopilot play, target 15 fps capture):
  47 frames captured, **capture 4.8 fps**, game rendering **≈5 fps**,
  encode 1.8 s (**≈26 encode-fps**), output MP4 valid — H.264 + AAC,
  1280×720, 3.13 s, **A/V sync offset 0.000 s**. The health monitor
  correctly flagged MISSING_FRAMES / LOW_CAPTURE_FPS and the
  recovery budget was spent and stopped (3 + 3 attempts), exactly as
  designed — the frames this VM never rendered cannot be recovered.
- **1080p run**: 22 frames in 3 s (capture 2.8 fps), encoded to a
  valid **1920×1080** H.264/AAC MP4 in 1.9 s with no fallback needed.
  Frames are the 720p viewport scaled up by the capture manager —
  this VM's window is 1280×720; native 1080p rendering needs a
  1920×1080 display target.
- **Continuous segmentation**: 13 s of continuous recording at a
  3 s segment setting produced **21 valid segments** (4.87 MB total)
  in the merged runner run — more, shorter segments than the nominal
  setting, because segment timing is wall-clock while encodes block
  the main loop on this slow VM (see limits). Every segment passed
  ffprobe validation. Across all runs the suites recorded **≈40 s of
  real gameplay** and produced **27+ valid MP4 segments**, kept as
  local evidence under `recordings/` (gitignored).

## Honest limits

- **This VM has no GPU and no real display.** Rendering is llvmpipe
  software GL under Xvfb: the game itself renders at ≈5 fps at 720p,
  so real-time 1080p60 (or even 720p30) capture is **not** proven
  here and cannot be on this hardware. What is proven: the complete
  pipeline mechanics — capture, mix, encode, validation, segmenting,
  storage caps, recovery — at the rates this machine can sustain,
  with configurable targets up to 1920×1080@60 for hardware that can.
- Capture grabs the root viewport, so the HUD and the broadcast
  overlay are in the picture by design (it is a broadcast feed, not
  a clean gameplay render).
- Frame transport is a PNG sequence (lossless intermediate, single
  final encode — no generation loss from re-encoding). A pipe-based
  zero-copy path is a possible later optimization, not implemented.
- Segment rollover timing is wall-clock; a blocking encode longer
  than the segment duration makes the following segment start late
  and the next rollover come early. On hardware that encodes faster
  than real time this does not occur.
- Missing-frame / low-capture-fps recovery is bounded and honest:
  it restarts the capture session at the next segment boundary; it
  cannot invent frames that were never rendered.
- GPU usage is reported as unavailable (no GPU); CPU/RAM come from
  Godot's Performance monitors.
- RTMP: command construction and the enable-gate are implemented
  and tested; **no stream was started**, per the phase scope.

## Tests

- Logic suite (headless): `godot --headless --path game res://tests/VideoTest.tscn` — 71 checks.
- Capture suite (Xvfb): `xvfb-run -a godot --path game res://tests/VideoCaptureTest.tscn` — 13 checks.
- Both, merged into `tests/video_output.txt`: `GODOT=<godot binary> bash tests/run_video_tests.sh`.
- Full report: `tests/TESTING_REPORT_PHASE06.md`.
