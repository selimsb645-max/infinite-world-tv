# Testing report — Phase 06 (Automated Video Production & Rendering Engine)

Date: 2026-11-24. Machine: this VM — 4 vCPU, ~8 GB RAM, **no GPU**
(llvmpipe software GL under Xvfb for the capture half), Godot
4.3.stable, FFmpeg 8.1.2.

## Suites

| Suite | Command | Result |
|---|---|---|
| Video logic (headless) | `godot --headless --path game res://tests/VideoTest.tscn` | **71/71 PASS**, `VIDEO_LOGIC_DONE failures=0` |
| Video capture (Xvfb, real pixels) | `xvfb-run -a godot --path game res://tests/VideoCaptureTest.tscn` | **13/13 PASS**, `VIDEO_CAPTURE_DONE failures=0` |
| Combined | `GODOT=<binary> bash tests/run_video_tests.sh` | `tests/video_output.txt`, **84 PASS / 0 FAIL**, `VIDEO_DONE failures=0` |

## What the logic suite covers (71 checks)

EncodingConfig presets/validity/fallback · FFmpegManager
availability, encode-arg construction (libx264, AAC, yuv420p,
bitrate, pinned duration), RTMP arg tail, streaming gate
(off by default, off with URL only, on only when enabled) ·
real testsrc encode + ffprobe validation, missing-audio detection ·
AudioMixer plan (music + world ambience + events, missing clip
skipped, per-layer gains from config), real mix render (duration
matches segment to 0.01 s), silent-plan render · segment naming,
partial/finalize rules (missing and empty refused), interrupted
recovery (garbage partial discarded, real partial recovered) ·
StorageManager usage accounting, count cap (oldest deleted), size
cap, retention sparing the protected file · CaptureHealthMonitor
(healthy verdict + all 7 issue detections) · VideoRecoveryManager
(action mapping, bounded give-up after 3 attempts, per-issue
budgets, reset) · BroadcastOverlayManager state roundtrip and
branding on/off · CameraController distance-scale apply + clamp,
CameraCaptureController null-safety · GameCaptureManager
headless begin/end safety.

## What the capture suite covers (13 checks, real gameplay)

The Phase 04 autopilot plays the real game (seed 777) while the
Phase 06 pipeline records:

- Overlay is rendered into captured frames (pixel-hash changes when
  the overlay is hidden) and its state is live (world = Space World
  in the measured run).
- **720p end-to-end**: 47 frames in 6 s → MP4 (H.264 + AAC,
  1280×720, 3.13 s) passes ffprobe validation; A/V sync offset
  0.000 s; measured capture 4.8 fps, game ≈5 fps, encode ≈26 fps.
  Health monitor flagged MISSING_FRAMES + LOW_CAPTURE_FPS; recovery
  spent its bounded budget (3 + 3) and stopped.
- **1080p configuration**: valid 1920×1080 H.264/AAC MP4 (frames
  scaled from the 720p viewport — see PHASE06.md limits), no
  fallback needed.
- **Continuous segmentation**: 13 s at a 3 s segment setting → 21
  valid segments, 4.87 MB (runner run; earlier manual run: 14
  segments, 3.23 MB). All segments ffprobe-valid.
- `stop_and_render()` with no recording returns `not_recording`
  gracefully.

## Evidence files (local, gitignored)

`recordings/run_a/*.mp4` (720p segments), `recordings/run_b/*.mp4`
(1080p), `recordings/run_c/*.mp4` (segmentation run) — 27+ MP4s
across the suite runs. One leftover `.partial.mp4` in run_b is from
an earlier interrupted manual run and is exactly what startup
recovery judges on the next launch.

## Regressions (all re-run after Phase 06 changes)

| Suite | Before Phase 06 | After Phase 06 |
|---|---|---|
| Phase 02 smoke | 26/26 | **26/26 PASS** |
| Phase 03 generation | 45/45 | **45/45 PASS** |
| Phase 04 autopilot | 29/29 | **29/29 PASS** |
| Phase 05 asset | 237/237 | **237/237 PASS** |

## Not proven on this machine (stated plainly)

Real-time capture at 1080p60 / 720p30 (the game renders ≈5 fps
under llvmpipe), native-resolution 1080p rendering (needs a
1920×1080 display target), GPU encoding/usage metrics, and any
live RTMP streaming (out of scope for this phase; gate tested,
stream never started).
