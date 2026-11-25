# Testing report — Phase 07 (YouTube Live Streaming & 24/7 Broadcast Infrastructure)

Date: 2026-11-24. Machine: this VM — 4 vCPU, ~8 GB RAM, **no GPU**,
Godot 4.3.stable, FFmpeg 8.1.2. All streaming processes ran against
ffmpeg's own RTMP listener on 127.0.0.1 with a fake key
(`FAKEKEY-test-7f3d9a-NOT-REAL`). **No YouTube endpoint was
contacted and no real stream key exists in these tests.**

## Suites

| Suite | Command | Result |
|---|---|---|
| Stream (headless logic + real local-RTMP processes) | `godot --headless --path game res://tests/StreamTest.tscn` | **51/51 PASS**, `STREAM_DONE failures=0` |
| Combined runner | `GODOT=<binary> bash tests/run_stream_tests.sh` | `tests/stream_output.txt`, **51 PASS / 0 FAIL** |
| Regression: smoke | `godot --headless --path game res://tests/SmokeTest.tscn` | **26/26 PASS**, `SMOKE_DONE failures=0` |
| Regression: generation | `godot --headless --path game res://tests/GenerationTest.tscn` | **45/45 PASS**, `GEN_DONE failures=0` |
| Regression: autopilot | `godot --headless --path game res://tests/AutopilotTest.tscn` | **29/29 PASS**, `AUTOPILOT_DONE failures=0` |
| Regression: asset | `godot --headless --path game res://tests/AssetTest.tscn` | **237/237 PASS**, `ASSET_DONE failures=0` |
| Regression: video | `GODOT=<binary> bash tests/run_video_tests.sh` | **84/84 PASS**, `VIDEO_DONE failures=0` |

## What the stream suite covers (51 checks)

**Config & secrets (17).** Test inputs generated (240 PNG frames +
tone WAV) · default keyframe interval is 2 s (YouTube's
recommendation) · default ingest is RTMPS · a complete config
validates · missing key is flagged as
`missing_credentials:IWT_YOUTUBE_STREAM_KEY` (name, never a value) ·
keyframe interval 5 s rejected (YouTube maximum is 4 s) · non-RTMP
ingest rejected · `redact()` masks the key inside a full RTMPS URL ·
`summary()` and `safe_url()` show `key=set`/`***`, never the key ·
`full_url()` does carry the key (the single sanctioned place: the
process arguments) · backoff doubles 2/4/8/16 and caps at 60 ·
key loads from the environment variable · key + visibility load
from a `.env` file · a missing `.env` file is a safe no-op.

**Health monitor (4).** ffmpeg `-progress` parsing takes the last
complete block (frame/fps/bitrate/drop counters exact) · a dead
process is flagged PROCESS_DEAD · a silent progress file past the
stall timeout is flagged OUTPUT_STALLED · the snapshot carries
uptime, dropped frames, reconnect count, last error, CPU and RAM.

**Admin & preparation (8).** Prepare succeeds and **spawns
nothing** (pid −1, state PREPARED) · prepare rejects a missing
audio input · prepare + start without credentials are refused and
no process exists · every sensitive action (start, stop, logs,
auto-recovery, quality) refuses a wrong token · an admin with no
token configured refuses even the correct-looking token.

**Real local streaming (8).** ffmpeg streams the frame sequence +
tone to the local RTMP listener: start succeeds · progress reports
frames flowing (25 frames inside the first second at the 24 fps
test rate; measured fps 25.0) · a second start is refused
(`already_running`, same pid) · the live snapshot shows uptime,
target fps, measured fps, dropped frames, reconnect count 0 ·
quality change is refused mid-stream · graceful stop leaves no
process and releases the lock file · **the listener's recording
probes as H.264 video + AAC audio** — the full publish path works.

**Public safeguard (3).** With visibility `public`, start without
the confirmation flag is refused (`public_confirmation_required`,
no process, still PREPARED) · with the explicit flag it starts —
against the local listener only · the stream flows.

**Crash recovery (4).** A flowing stream's encoder is killed with
SIGKILL · the manager detects the death, counts the reconnect and
respawns onto a fresh listener (new pid, state STREAMING) · the
second listener's recording probes as valid H.264 + AAC — the
recovered stream really carries picture and sound.

**Network interruption (2).** The listener is killed mid-stream ·
the manager counts a network interruption and schedules a
reconnect (observed state RECOVERING, interruptions=1,
reconnects=1).

**Reconnect limits (5).** Against a dead port with a budget of 2:
the start is attempted · the manager gives up into state FAILED ·
attempts equal exactly 2 · five extra `poll()` calls and 2 s of
waiting change nothing (no hidden retry loop) · with
auto-recovery disabled, the first failure is final (FAILED,
0 attempts).

**Redaction sweep (2).** After all sessions above: every manager's
logs + statuses + config summaries + the on-disk JSON-lines log
are concatenated and searched — the fake key is absent · and the
sanity counter-check: the built process arguments **do** contain
it, proving the sweep was not vacuous.

## Bug found by the suite

First run: 44/51 (7 failures). Process-death detection failed for encoders that
had been running (crash, network and graceful-stop checks) while
instant-exit processes were detected fine. Root cause: the
original liveness check read `/proc/<pid>/stat` through
`FileAccess.get_as_text()`; for an unreaped zombie child the read
path returned content that parsed as "alive", so a dead encoder
looked immortal. Fix: liveness now uses `ps -o stat=` (no output =
gone, leading `Z`/`X` = dead), with `kill -0` only as a fallback
when `ps` itself is missing. Re-run: **51/51 PASS** and the full
suite completes in ~36 s (the stop path no longer burns its 2.5 s
SIGKILL wait on zombies). One test was also strengthened:
post-recovery flow is now proven by probing the second listener's
recording instead of trusting a cumulative frame counter.

## Not executed (with reasons)

| Test | Why not |
|---|---|
| Private/unlisted YouTube test stream; RTMPS handshake against `a.rtmps.youtube.com`; Live Control Room verification | No stream key exists; creating/using one and going live (even privately) was outside this phase's authority. This is the owner's supervised first test — steps in `docs/PHASE07.md` |
| YouTube Data API broadcast creation/binding | Same as above; the design deliberately needs no API for the RTMP push path, and no OAuth credentials exist |
| Long-duration (6 h) GitHub Actions stability session | Exceeds this environment's session limits; Actions job behaviour is documented, not measured here |
| Real-time 1080p / 720p30 streaming rates | This VM renders the game at ≈5 fps (llvmpipe, Phase 06 measurement); process tests ran at 320×240@24 so the *mechanics* are real, the *rates* await real hardware |
| Outbound RTMP publish through this VM's network | A bare TCP connect to port 1935 succeeded from the shell, but no RTMP publish was attempted (see above); hosted-VM egress policy for sustained RTMP remains unverified |
