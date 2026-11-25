# Phase 08 — Central Admin Dashboard & System Monitoring

A centralized, authenticated dashboard over the real Phase 02–07
system. **Every value it shows comes from an actual source** —
process state, `/proc`, the modules' own snapshots and log files.
There are no simulated metrics and no fake status indicators
anywhere in the production dashboard: a module that is not running
is labelled STOPPED / OFFLINE / NOT CONFIGURED, and on a machine
with no stream key the streaming module correctly reads
NOT CONFIGURED.

## Architecture

```
                ┌────────────────────────────┐
  Browser ─────▶│ dashboard/server.py        │  Python 3 stdlib
                │  auth + sessions + audit   │  (http.server only)
                │  status / logs / alerts    │
                └──────┬───────────┬─────────┘
              pidfiles│     command/status files (JSON, atomic)
                ┌──────▼───┐  ┌────▼──────────────┐
                │ Game     │  │ Stream service    │
                │ service  │  │ (persistent)      │
                │ (bridge) │  │ StreamAdmin ──────┼─▶ Phase 07
                └──────┬───┘  └───────────────────┘    StreamManager
                       │ reads live fields
                GameManager / AutonomousController /
                VideoRenderer  (Phases 02 / 04 / 06)
```

Three layers, deliberately separated (spec section 11):

1. **Dashboard backend + UI** — `dashboard/` (new top-level folder).
   `server.py` (HTTP, routing, auth), `status_service.py`
   (aggregation), `process_control.py` (service lifecycle +
   command round-trips), `log_service.py`, `alert_service.py`,
   `redact.py`; the frontend is static `index.html` / `style.css` /
   `app.js` — vanilla, no build step, no CDN, no framework.
2. **Godot-side bridges** — `game/dashboard/` (additive; no earlier
   file modified):
   - `GameService.tscn` + `dashboard_bridge.gd`: instances the
     normal Main scene and, **only when `IWT_DASHBOARD_DIR` is
     set**, writes `game_status.json` every second from live
     GameManager / AutonomousController / gameplay RecoveryManager
     / VideoRenderer fields, and executes `game_cmd.json` commands
     against those same objects.
   - `StreamService.tscn` + `stream_service.gd`: a persistent
     headless process owning the real Phase 07 StreamManager +
     StreamAdmin pair (so its monitoring/recovery loop stays
     alive), writing `stream_status.json` from
     `StreamAdmin.check_health()` every 0.5 s and executing
     `stream_cmd.json` through StreamAdmin.
3. **Existing modules** — unchanged. The dashboard reuses
   StreamAdmin's authorization, StreamManager's lock discipline,
   CaptureHealthMonitor's evaluation and the Phase 07 redaction
   rules instead of duplicating any of them.

## Run it

```bash
export IWT_ADMIN_TOKEN=...            # required for login (SECRET)
export IWT_VIEWER_TOKEN=...           # optional, read-only role
export IWT_GODOT_BIN=/path/to/godot   # or have `godot` on PATH
export IWT_YOUTUBE_STREAM_KEY=...     # only when streaming is set up
python3 dashboard/server.py           # http://127.0.0.1:8787
```

Configuration (environment only; nothing is stored in the repo):
`IWT_DASHBOARD_HOST` (default `127.0.0.1`), `IWT_DASHBOARD_PORT`
(8787), `IWT_DASHBOARD_RUNTIME` (default `dashboard/runtime/`,
gitignored), `IWT_RECORDINGS_DIR`, `IWT_GODOT_LOG`,
`IWT_GAME_DISPLAY_MODE` (`auto` | `headless` | `windowed`), plus
the Phase 07 stream variables, which the dashboard passes through
to the stream service process it spawns.

## API

All `/api/*` endpoints except login require the session cookie.

| Endpoint | Role | Returns |
|---|---|---|
| `POST /api/login` `{token}` | — | session cookie + role |
| `POST /api/logout` | any | clears the session |
| `GET /api/status` | admin, viewer | full aggregated status |
| `GET /api/alerts` | admin, viewer | active + recent alerts |
| `GET /api/logs?source=&module=&severity=&q=&limit=` | admin | filtered log entries (redacted) |
| `GET /api/logs/export?...` | admin | plain-text diagnostics download |
| `POST /api/control` `{action, ...}` | admin | the actual operation result |

Control actions: `health_check`; `game_start` / `game_stop` /
`game_restart`; `game_command` with `command` ∈ `start_ai`,
`start_game`, `pause_ai`, `resume_ai`, `restart_game`,
`quit_to_menu`, `rendering_start`, `rendering_stop`,
`rendering_restart`, `health_check`, `quit`;
`stream_service_start` / `stream_service_stop` /
`stream_service_restart`; `stream_command` with `command` ∈
`prepare`, `start`, `stop`, `restart`, `health`,
`set_auto_recovery`, `configure_quality` (fields `confirm_public`,
`preset`, `enabled` as applicable). Stream commands auto-start the
stream service if it is down and say so in the result
(`service_boot`).

## Status model — where every number comes from

| Field | Source |
|---|---|
| CPU % | two `/proc/stat` samples, 0.15 s apart |
| RAM | `/proc/meminfo` (MemTotal / MemAvailable) |
| Disk | `shutil.disk_usage` on the recordings dir |
| Game state / world / level / seed / difficulty / mode / score / progress / FPS | `game_status.json`, written by the bridge from live GameManager fields (`Engine.get_frames_per_second()` for FPS) |
| AI status + decisions / levels / success rate | `AutonomousController.stats()` via the bridge |
| Generation status | bridge: `endless_active`, generated level seed + `difficulty_index` |
| Rendering | bridge: VideoRenderer `recording` / `continuous` / `segment_index` / `perf`, recovery attempts; plus the real recordings dir (segment count, bytes, latest mtime) |
| Streaming | `stream_status.json` from `StreamAdmin.check_health()` (StreamHealthMonitor snapshot: uptime, resolution, target/measured fps + bitrate, dropped frames, ffmpeg pid/liveness, reconnect + interruption counters, last error / recovery) |
| Monitoring / recovery | dashboard uptime, last health-check record, StreamConfig `auto_recovery`, reconnect attempts, VideoRecoveryManager attempts, gameplay recovery events |

Status labels are exactly the spec's set: ONLINE, OFFLINE,
RUNNING, STOPPED, WARNING, ERROR, NOT CONFIGURED. Overall health:
ERROR if any module is ERROR, else WARNING if any is WARNING, else
ONLINE if anything is RUNNING, else OFFLINE.

## Controls — semantics and limits

- **Game start/stop/restart** manage the GameService process
  (pidfile + zombie-aware liveness; duplicate start is refused
  with `already_running`). Display mode `auto` uses a real display
  if present, else `xvfb-run`, else `--headless`. The game is not
  installed as a system service on this VM — process control here
  is the honest mechanism, and it is documented as such.
- **Start/Pause/Resume AI** act on the real AutonomousController
  (`start_autonomous(seed)`; pause = decision loop halted +
  autopilot input released; resume re-enables it while PLAYING).
- **Rendering start/stop/restart** call `GameManager.setup_broadcast`
  + the VideoRenderer's real `start_continuous` / `stop_continuous`.
- **Stream controls** execute inside the persistent stream service
  through Phase 07's StreamAdmin. **The Phase 07 safeguard is not
  weakened**: a public start needs the admin session here AND the
  separate `confirm_public` flag, which StreamAdmin enforces; the
  UI additionally asks for explicit confirmation.
- **Automatic recovery toggle** maps to the real
  `StreamConfig.auto_recovery` via StreamAdmin. The Phase 04/06
  recovery managers are bounded-by-construction with no disable
  switch in the existing code; their state is displayed, and there
  is deliberately no fake toggle for them.
- Every control returns the backend's actual result; the UI shows
  success/failure only from that response.

## Security

- **Authentication**: a token (env `IWT_ADMIN_TOKEN`, or
  `IWT_VIEWER_TOKEN` for read-only) is exchanged for an HttpOnly,
  SameSite=Strict session cookie (12 h). Tokens are compared in
  constant time, held only in process memory / the environment,
  never written to disk, never logged, never returned by the API.
- **Authorization is server-side on every sensitive endpoint**:
  controls and logs require the admin role (viewer gets 403);
  status and alerts allow both roles. The frontend's button
  visibility is cosmetic only.
- **Login rate limiting**: 5 failed attempts per IP inside
  5 minutes locks `/api/login` for that IP (HTTP 429) until the
  window passes.
- **Audit log**: every control action appends
  `{ts, actor: role, action, ok}` to `audit.jsonl` — roles, never
  credentials.
- **Redaction**: all API output passes through `redact.py` (exact
  secret values from the environment + ingest-URL key patterns),
  on top of StreamManager's own redaction at the source.
- **Exposure**: the server binds to localhost by default. Putting
  it on a network is the operator's decision and must go through a
  TLS-terminating reverse proxy; the dashboard itself speaks plain
  HTTP and offers no built-in TLS.

## Alerts

A background evaluator (15 s tick) writes state transitions to
`alerts.jsonl` for: stream FAILED, stream network interruptions,
CPU/RAM > 90%, stream reconnect attempts ≥ 3, recordings disk
> 90% used (> 95% = error), stream configuration errors (while the
service runs), and unexpected game-process exit. Local file only —
free, no external service. **Not implemented**: outbound webhook /
email delivery (no configured endpoint exists; adding one is a
config decision for the operator, and no paid service will be
introduced for it).

## Limitations (honest)

- **No gameplay preview** — the game renders on its own surface;
  the pipeline exposes status, not frames, to the dashboard. The
  UI says so instead of showing a fake preview.
- The Godot engine log (`godot.log`) has no per-line timestamps;
  its entries are served with `ts: null` rather than invented
  times.
- Stream status is as fresh as the stream service's 0.5 s
  snapshot; if the service dies, the section degrades to OFFLINE /
  WARNING from process liveness instead of freezing on old data —
  the game section behaves the same way (1 s snapshot + liveness).
- Roles are exactly two (admin / viewer): the existing
  architecture has no user database, and none was invented.
- On this VM the expected resting state is: game STOPPED,
  streaming NOT CONFIGURED (no stream key exists), rendering
  OFFLINE. Those are correct readings, not faults.

## Tests

```bash
GODOT=/path/to/godot bash tests/run_dashboard_tests.sh
# Expected: DASHBOARD_DONE failures=0 (45 checks) —
# tests/dashboard_output.txt
```

The suite starts two real server instances over HTTP. Instance A
(no stream key): page + viewport + responsive CSS served, 401
without a session, wrong-token 401, admin/viewer logins, role
enforcement (viewer 403 on controls and logs), NOT CONFIGURED /
STOPPED / OFFLINE status truth, health-check round-trip, audit log
written without tokens, severity filtering, login rate limiting
(429). Instance B (fake key, ingest pointed at a dead local port —
nothing leaves the machine): game start + duplicate refusal, AI
start/pause/resume with status read back from the real bridge
snapshot, stream prepare, public-start refusal without
confirmation, confirmed start/stop, stream health, quality
configuration, auto-recovery toggle, a planted log line carrying
the fake key proven redacted in logs/status/export, game +
stream-service stop, and status still correct with modules
offline. Mobile responsiveness is verified mechanically (viewport
meta present + `@media` single-column rules in the served CSS) —
no device farm exists here, and the doc says exactly that.
