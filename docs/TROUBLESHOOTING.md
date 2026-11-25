# Troubleshooting & Recovery Guide — INFINITE WORLD TV

Symptoms → likely cause → what to do. Everything here refers
to mechanisms that actually exist in the code (Phases 06–09);
where the honest answer is "this cannot work on this
hardware", it says so.

## First checks for any problem

1. Open the dashboard (http://127.0.0.1:8787 by default) —
   Overview shows each module's real label.
2. Check the supervisor status:
   `python3 dashboard/supervisor.py --status`
   (states, pids, restart counts, last crash snapshots).
3. Read the logs before restarting anything: dashboard Logs
   view, or the runtime dir (`*.jsonl`, `*_process.log`,
   `crashes/`). Restarting first destroys the evidence the
   supervisor deliberately preserves.

## Symptoms

### Test runners report failures=999 / units "spawn_failed: 'godot'"
The shell runners and the stability driver do not bundle a
Godot path: `tests/run_*_tests.sh` use `$GODOT` (default
`godot` from PATH) and the supervisor/stability driver uses
`$IWT_GODOT_BIN` (default `godot`). On a machine where Godot is
not on PATH, every suite records the 999 "did not run" sentinel
(or the game/stream units fail to spawn) even though the code
is fine. Fix: export both variables to the real binary first,
e.g. `GODOT=$HOME/workspace/tools/godot/Godot_v4.3-stable_linux.x86_64`
and `IWT_GODOT_BIN=<same path>`, then re-run. (Hit and verified
during the Phase 05.1 regression run, 2026-11-25.)

### Dashboard shows game STOPPED / streaming NOT CONFIGURED

- Streaming `NOT CONFIGURED` with no stream key in the
  environment is the **correct** state, not a fault. Set
  `IWT_YOUTUBE_STREAM_KEY` (see `docs/DEPLOYMENT.md`) only
  when a real test is intended.
- Game `STOPPED`: start it from the dashboard Controls, or
  check the game unit in the supervisor status. If the unit
  is `FAILED`, the restart budget (5 per 600 s) was exhausted
  — read `crashes/game_*.log` for the cause, fix it, then
  reset via the supervisor/dashboard.

### Game process keeps crashing (restart loop that stops)

Working as designed: the supervisor backs off exponentially
(2 s × 2ⁿ, capped) and marks the unit `FAILED` after the
budget instead of looping forever. The crash-log snapshot
written before each restart is the diagnostic. Common real
causes on a new host: wrong Godot path (`IWT_GODOT_BIN`),
missing Xvfb for a windowed game unit, or a corrupted
`.godot` import cache (delete `game/.godot/` and re-import).

### Stream disconnects and reconnects repeatedly

- Check the dashboard streaming section: reconnect count,
  last error. The manager retries with a bounded budget
  (default max 5) and then reports `FAILED` — it will not
  hammer YouTube forever.
- Verify the ingest URL and that the key is set
  (`has_stream_key` in the stream status snapshot — the key
  itself is never displayed).
- A dead local ingest in tests (`rtmp://127.0.0.1:19359`)
  refusing connections is expected behaviour, used by the
  suites on purpose.

### Public start is refused (`public_confirmation_required`)

By design. Starting a public broadcast needs the admin token
**and** the explicit confirmation flag in the same action.
Private/unlisted starts do not need the flag. There is no
configuration-only path around this.

### Video segments are produced but capture health complains

`MISSING_FRAMES` / `LOW_CAPTURE_FPS` on a no-GPU machine is
the health monitor telling the truth: the game itself is
rendering at ≈3–5 fps (llvmpipe), so capture cannot do
better. The Phase 06 recovery restarts capture within its
budget; the segments still encode and validate. The fix is
hardware (see `docs/DEPLOYMENT.md` host requirements), not
settings. Do not silence the monitor to make it look green.

### A rendered MP4 fails validation

`FFmpegManager.validate()` reports the specific issue
(codec, resolution, duration, A/V sync). Check
`recordings/` for `.partial.mp4` files: a partial means the
recording was interrupted; the segment manager finalises
only validated files, and orphaned partials are reclaimed
by the storage policy (Phase 09). One known cosmetic wart
(Phase 10): a single late frame-save error can appear in
the game log right at segment finalisation — the segment
still validates; it is a race between the last captured
frame and the frames-dir cleanup, not data loss.

### Disk filling up

Recordings are capped by the Phase 06 `StorageManager`
(retention + size + count caps, oldest first, newest
protected). Dashboard/audit/alert logs rotate at 5 MB × 3
(Phase 09). If the disk still fills, check for files
*outside* those policies (e.g. core dumps, editor caches)
and read the alert log — `disk >90%` raises an alert before
it becomes an outage.

### Dashboard login fails / 429

- Wrong token → 401. Tokens come from `IWT_ADMIN_TOKEN` /
  `IWT_VIEWER_TOKEN` in the server's environment — the same
  values the stream service uses for admin actions.
- Repeated failures trigger the login rate limit (429 for
  several minutes). Wait it out; do not restart the server
  to bypass it (the audit log records the attempts).

### Everything is down after the host rebooted

The supervisor is a process, not a boot service, unless the
operator installs it as one. After a host restart, start it
again (`docs/RUNNING.md`, Phase 09 section) — units come
back in order and the dashboard reflects reality within
seconds. For unattended reboots, wrap `dashboard/supervisor.py`
in a systemd unit on the host (operator's choice; the
supervisor itself is deliberately init-system-agnostic).

## Recovery behaviour you can rely on (all test-proven)

| Failure | Detection | Recovery | Limit |
|---|---|---|---|
| Game/stream/dashboard process killed | Supervisor liveness (zombie-aware) + crash snapshot | Restart with exponential backoff | 5 restarts / 600 s, then `FAILED` |
| ffmpeg stream process dies | StreamManager progress/liveness | Bounded reconnect with backoff | Configured max attempts, then `FAILED` |
| Capture stalls / missing frames | CaptureHealthMonitor | Restart capture; 720p fallback path exists | Windowed budget (3 / rolling hour) |
| AI wedged in a level | RecoveryManager stuck detection | Bounded restarts, then skip level | Per-level restart cap |
| Invalid generated level | LevelValidator at generation | Retry with new seed, then validated fallback template | Bounded retries |
| Interrupted recording | `.partial.mp4` marker | Never finalised; reclaimed by storage policy | Age-based |
| Dashboard module offline | Status freshness checks | Dashboard stays up, labels the module OFFLINE | — |

## What recovery cannot do

- It cannot recover the **host** itself (power, VM
  termination, host disk death). State worth keeping lives
  in git (code) and in the owner's YouTube account
  (channel) — recordings are disposable by design.
- It cannot make a slow host fast: below real-time render
  rates, recovery keeps the pipeline *correct*, not
  *watchable*.
- It cannot reconnect a stream whose key was reset or
  whose channel lost live eligibility — that needs the
  owner in YouTube Studio.
