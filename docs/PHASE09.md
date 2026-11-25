# Phase 09 — Reliability, Fault Recovery & Long-Run Stability

Phase 09 is hardening, not features. It began with a full audit of
Phases 02–08 (code read, not assumed), produced the prioritized
issue list below, fixed the real gaps in place — reusing the
existing recovery machinery instead of duplicating it — and proved
the fixes with a new fault-injection suite (51 checks) plus a
measured 600-second supervised stability run. Nothing in this
document claims a duration or a result that was not actually run;
see "Executed / Simulated / Not executed" at the end.

## 1. Audit — what already existed (verified in code)

| Area | Existing mechanism | Verdict |
|---|---|---|
| Stream reconnect | `StreamManager`: bounded attempts + exponential backoff, pid-checked lock file, zombie-aware liveness | Sound |
| Video recovery | `VideoRecoveryManager`: per-issue action planner, max 3 attempts | Sound logic, flawed budget (issue #5) |
| Recording storage | `StorageManager.enforce()`: retention + size + count caps, oldest-first, protected newest | Sound for finalized segments only (issue #4) |
| Interrupted recordings | `VideoSegmentManager.recover_interrupted()`: ffprobe-judged promote-or-discard at renderer startup | Sound |
| Level generation | `LevelGenerator`: validator + anti-repetition, ≤8 retries, guaranteed fallback; history capped at 250 | Sound; fallback unchecked (issue #9) |
| AI stuck recovery | `RecoveryManager`: jump/reverse → level restart (≤2) → give up + fresh level | Sound ladder; unsafe inputs (issue #6) |
| Dashboard control | `process_control.py`: pidfile start/stop, zombie-aware, actual results | Start/stop only — no supervision (issue #1) |
| Alerts | `alert_service.py`: real conditions, transition-deduped | Detection without an actor; self-failure silent (issues #1, #7) |

## 2. Prioritized reliability issue list

**P1 — #1 No process supervision.** Nothing restarted a dead host
process. Phase 07's reconnect lives *inside* the StreamService
Godot process; if that process dies, the recovery logic dies with
it. Same for GameService and the dashboard backend. The alert
service could notice a game crash but no component acted.
→ **Fixed:** `dashboard/supervisor.py` (below).

**P1 — #2 Unbounded log growth (dashboard layer).**
`dashboard_log.jsonl`, `audit.jsonl`, `alerts.jsonl`,
`game_process.log`, `stream_process.log` were append-only
forever. On a weeks-long run they fill the same disk the
recordings live on. → **Fixed:** `dashboard/logrotate.py`
(5 MB × 3 siblings) wired into every writer.

**P1 — #3 Unbounded stream log (Godot layer).**
`StreamManager._log_entries` grew forever in memory and
`_flush_log_file()` rewrote the *entire* file on *every* event —
O(n²) I/O and an unbounded file in the one process meant to run
for weeks. → **Fixed:** 1,000-entry in-memory cap, append-one-line
writes, one-time rewrite from the capped window past 8 MB.

**P2 — #4 Orphaned partials escaped the storage caps.**
`StorageManager.usage()` counts `.partial.mp4` files but
`enforce()` only deleted finalized segments, and partial recovery
ran only at renderer startup — repeated encode failures inside
one long session accumulated partials the caps could never
reclaim. → **Fixed:** `enforce()` now reclaims partials older
than `EncodingConfig.partial_max_age_sec` (default 3600 s),
never the protected/in-progress one.

**P2 — #5 Recovery budgets never replenished.**
`VideoRecoveryManager` attempts were lifetime-of-process: three
transient `ENCODE_FAILURE`s, even months apart, permanently
disabled recovery for that issue. → **Fixed:** budgets are
windowed (default 3 attempts per rolling 3600 s, configurable;
clock injectable for tests).

**P2 — #6 AI dereferenced a possibly-null controller.**
`AutonomousController._physics_process` and
`PerceptionManager.sense()` used `game.active_controller()`
without a null check, and `RecoveryManager.update()` indexed
`p["pos"]` unguarded — during mode switches / level loads,
perception unavailability produced script errors instead of safe
degradation. → **Fixed:** `sense()` returns a well-formed
snapshot with `"available": false`; the controller holds course
for that interval; the recovery manager returns `none` on
missing data.

**P3 — #7 The monitor's own failure was silent.**
`alert_service` swallowed every evaluation exception by design
("never take the dashboard down") — including forever.
→ **Fixed:** consecutive errors and the last error are recorded;
at 3 consecutive failures a `monitor_degraded` alert is written
(and a resolved entry when it recovers).

**P3 — #8 Stream stall detection rides the host main loop.**
`StreamManager.poll()` is driven from `_process`; a hitched host
delays stall detection by the hitch. Documented, not changed —
the supervisor's process-level liveness (#1) is the backstop.

**P3 — #9 Fallback template was never validated.**
The guaranteed-valid fallback was hand-built and trusted.
→ **Fixed:** it is validated before serving; failures increment
`fallback_validation_failures` (the level is still served —
availability — and the soak asserts the counter stays 0).

**P3 — #10 The supervisor itself is a single point of failure.**
If `supervisor.py` dies, supervision stops (the units keep
running; nothing restarts them). Mitigations today: its lock is
pid-checked so a replacement can start cleanly, and its status
file goes stale visibly. Running it under the host's init system
is the operator-side answer (RUNNING.md); there is no init system
guarantee on free tiers — see §6.

## 3. What was implemented

* **`dashboard/supervisor.py`** — standalone supervisor
  (stdlib only) for the game, stream-service and dashboard
  units. Zombie-aware liveness; pidfiles shared with the Phase 08
  dashboard so the two never double-start (a dashboard-started
  unit is *adopted* and supervised); on unexpected exit it first
  preserves the unit log's tail to
  `crashes/<unit>_<timestamp>.log` (newest 5 kept), then restarts
  with exponential backoff (2 s × 2^n, cap 60 s); at most 5
  restarts per 600 s window per unit, then the unit is FAILED
  and stays down until an operator reset — no unbounded loop
  exists. Intentional stops are never restarted; stopping the
  game writes the dashboard stop marker so no false crash alert
  fires. Units are independent: one unit's crash loop never
  touches the others. Observable via `supervisor_status.json`
  and a rotated `supervisor.jsonl`. Its own duplicate instance
  is refused by a pid-checked, instance-aware lock (a flaw the
  new suite caught and fixed).
* **`dashboard/logrotate.py`** — rotation used by the dashboard
  log, audit log, alert log and (at process start) the game /
  stream process logs; the supervisor rotates its own log and
  unit logs the same way.
* **GDScript hardening** — windowed `VideoRecoveryManager`
  budgets; bounded append-only `StreamManager` logging;
  `StorageManager` partial reclamation +
  `EncodingConfig.partial_max_age_sec`; AI null-perception
  guards; validated generation fallback. All additive or
  semantics-preserving for the existing suites (all re-run green,
  §5).

## 4. Fault table (spec §4)

| Failure | Detection | Severity | Recovery action | Retry limit | Escalation | Diagnostics preserved |
|---|---|---|---|---|---|---|
| Game engine crash | Supervisor liveness (pidfile + /proc, zombie-aware); dashboard `game_crash` alert | error | Supervisor restart with backoff | 5 / 600 s | Unit FAILED, operator reset; alert entry | Crash snapshot (log tail), `game_process.log`, engine `godot.log` |
| Stream service host death | Supervisor liveness | error | Supervisor restart with backoff | 5 / 600 s | FAILED, operator reset | Crash snapshot, `stream_process.log` |
| Dashboard backend death | Supervisor liveness | error | Supervisor restart with backoff | 5 / 600 s | FAILED, operator reset | `dashboard_stdout.log`, snapshot |
| FFmpeg failure (in stream) | `StreamHealthMonitor`: progress-file stall + `ps` liveness | error | `StreamManager` reconnect with exponential backoff | `max_reconnect_attempts` (default 5) | Stream FAILED; operator acts via dashboard | Bounded `stream_log.jsonl`, health snapshot |
| Network interruption | Output-stall verdict; interruption counter increments | warn | Same bounded reconnect path | as above | FAILED + `stream_disconnect` alert | Health counters, stream log |
| Temporary network loss (whole host) | All units stall/fail independently | error | Per-unit bounded recovery when connectivity returns | per-unit budgets | FAILED units need operator reset | Supervisor + stream logs |
| Rendering / encode failure | ffprobe validation + `CaptureHealthMonitor` issues | warn→error | Re-encode → 720p fallback → audio-less encode → storage cleanup → capture restart at next segment | 3 per issue per 3600 s window | Segment marked failed (`give_up`), recording continues with next segment | `recovery_log`, segment result, startup partial recovery report |
| Invalid generated level | `LevelValidator` (+ anti-repetition) | warn | Regenerate with derived seed; else validated fallback template | 8 retries | Fallback served; `fallback_validation_failures` counter if the template itself ever fails | Generator counters (rejections, fallbacks) |
| AI controller unexpected state | Perception `available` flag; guarded recovery inputs | warn | Hold course one interval / no-op recovery action; stuck ladder jump→restart→fresh level | 2 restarts per level | Level abandoned for a fresh one | `PerformanceTracker` records, recovery event counts |
| Missing configuration | `StreamConfig.validate()` at prepare and at start; supervisor spawn failure for a missing binary | error | Refuse to start (no process, no loop at app level); supervisor bounds spawn failures like crashes | supervisor budget | FAILED + dashboard `config_error` alert | Validation error names (values are never logged), prepare result |
| Insufficient disk space | `StorageManager` caps + `headroom_ok`; dashboard `disk_low` alert at >90 % (warn) / >95 % (error) | warn→error | Retention → size cap → count cap, oldest-first; orphan-partial reclamation; `STORAGE_LOW` recovery cleanup | continuous | `headroom_ok == false` states plainly that continuous operation is impossible within the caps | Storage usage stats, alert entries |
| High CPU / RAM | Dashboard alerts at >90 % (from /proc) | warn | None automatic — healthy work is never killed by a monitor; the operator acts | n/a | Alert stays active until resolved | Status snapshots |
| Repeated recovery attempts | Alert `recovery_repeated` at ≥3 reconnects; supervisor window counters | warn | Budgets exhaust → FAILED instead of looping | as configured | Operator reset required | Supervisor status JSON, alert entries |
| Unexpected host shutdown | Cold start: stale pidfiles rejected by liveness, supervisor lock pid-checked, partials judged by ffprobe | error | Cold-start recovery paths (renderer startup recovery; supervisor fresh start) | n/a | Operator starts the stack (RUNNING.md) | Startup `recovery_log` entries, rotated logs survive |

## 5. Test results

### Executed

* **New reliability suite — 51/51 PASS,
  `RELIABILITY_DONE failures=0`** (`tests/reliability_output.txt`,
  runner `tests/run_reliability_tests.sh`):
  * GDScript half (24): partial reclamation (old deleted, fresh
    and protected kept, caps intact, `headroom_ok` truthfully
    false under a tiny quota); recovery window (exhaustion inside
    the window, per-issue independence, replenishment after it,
    reset); stream log bounds (memory capped at 1,000, file
    complete at 1,200 appended lines, size-bound rewrite after a
    planted 9 MB bloat, last line valid JSON); unprepared stream
    start refused; AI faults (null-controller perception safe,
    missing/partial perception degrades to `none`, normal path
    intact); **generation soak: 1,000 deterministic levels —
    1,000 valid on re-validation, 1,000 distinct fingerprints,
    3 candidate rejections absorbed by retries, 0 fallbacks,
    `fallback_validation_failures = 0`, history capped at 250,
    static-memory growth +1.80 MB**.
  * Python half (27): log rotation bounds total size and file
    count; supervisor start + duplicate refusal; SIGKILL of a
    healthy unit detected, crash snapshot preserved, backoff
    respected (no instant restart), restarted once and counted;
    intentional stop never restarted; crash-looping unit spawned
    exactly 1 + max_restarts times then FAILED and never again,
    start refused until operator reset, reset recovers; missing
    binary reported as a bounded spawn failure; a crash-looping
    unit reaches FAILED while a healthy unit is untouched;
    status file written; second supervisor refused by the lock;
    adoption of an externally started process works and it can
    be stopped.
* **Stability run — 600 s actual, `STABILITY_DONE failures=0`**
  (`tests/stability_output.txt`, driver `tests/stability_run.py`).
  The real stack under the supervisor: GameService + StreamService
  (headless) + dashboard backend, 60 samples at 10 s intervals.
  Injected faults: SIGKILL to the game at 240 s and to the stream
  service at 420 s — **both detected and recovered, exactly one
  restart each; the dashboard unit was never touched**. End
  states: all RUNNING. Recovery success rate for injected faults:
  2/2. Dashboard HTTP reachable in 59/60 samples.
  * RSS: game 2.9 → 98.8 MB (peak 103.0), stream 1.3 → 87.1 MB
    (peak 87.2), dashboard 1.1 → 14.7 MB (peak 21.6). The rise is
    engine warm-up in the first samples; end ≈ peak for both
    Godot units — no growth trend across the run's steady state.
  * CPU (share of one core): game avg 2.2 % (peak 8.2), stream
    avg 1.3 % (peak 4.2), dashboard avg 0.1 % (peak 1.3).
  * Game FPS from the bridge: median 145, min 74 — headless
    llvmpipe rendering of the menu scene, **not** gameplay-load
    FPS; it proves the bridge stayed live, nothing more.
  * Environment note: the Phase 02–08 regression suites ran
    concurrently during roughly the first half of the run on
    this shared 1.5-vCPU VM, so CPU/peak figures are loaded-VM
    numbers, not idle-machine numbers.
* **Regressions — all re-run after the Phase 09 changes, all
  green:** smoke 26/26, generation 45/45, autopilot 29/29,
  asset 237/237, video 84/84, stream 51/51, dashboard 45/45
  (every `*_DONE failures=0`).

### Simulated (fault reproduced against a stand-in, not the real target)

* Low disk space — exercised via tiny storage quotas in the
  GDScript suite (`max_storage_mb = 0.01`), not by filling the
  real recordings volume.
* Crash loops and missing binaries — dummy Python units under
  the real supervisor (the supervisor logic is the real target;
  the units are stand-ins by design).
* Network interruption — Phase 07's executed local-listener
  kill/reconnect tests stand as the evidence; not re-run against
  any external network.

### Not executed (with reasons)

* **1-hour, 6-hour, 24-hour and 7-day soaks** — exceed this
  session's runtime. Only the 600 s run above was executed; no
  longer duration is claimed anywhere.
* **Real YouTube ingest disconnect/reconnect** — no stream key
  exists and none may be created in this phase (Phase 07 rule).
* **Real disk-full on the system volume** — filling the VM's
  disk would endanger unrelated work; quota simulation used
  instead.
* **GPU / video-memory exhaustion** — this VM has no GPU
  (llvmpipe software rendering); VRAM is not measurable here.
* **Real host power loss / VM replacement drill** — cannot be
  induced from inside the guest; the cold-start recovery paths
  it would exercise (stale pidfiles, partial judging, lock
  re-acquisition) are unit-tested individually.
* **Alert-service degradation trigger** — the new
  consecutive-error counters and `monitor_degraded` entry are
  implemented and reviewed, but no test forced 3 consecutive
  evaluation failures in this phase.

## 6. Infrastructure reality check (spec §12)

* **Persistent runtime is mandatory.** The supervisor, game,
  stream service and dashboard must live on a host that stays
  on. This VM is a development sandbox: it is replaced on
  redeploys, and everything in it stops. It is not a broadcast
  host.
* **Compute:** the game renders in software here (llvmpipe,
  ≈5 fps at 720p measured in Phase 06) — a real broadcast needs
  a GPU or a much stronger CPU for 720p30/1080p30 capture +
  H.264 encoding. The supervisor/dashboard themselves are
  negligible (<25 MB RAM, <1 % CPU measured).
* **Storage:** recordings are capped by configuration
  (Phase 06/09), logs are now capped too (5 MB × 3 per file);
  a 24/7 1080p archive is a *policy* decision (retention), not
  an accident of disk size.
* **Bandwidth:** unchanged from Phase 07 — 1080p30 at YouTube's
  recommended bitrate is ≈3.2 TB/month of upload; free tiers
  with transfer caps cannot carry that.
* **Free-tier limits & sleep policies:** GitHub Actions jobs
  cap at 6 h and are CI, not hosting; free PaaS tiers sleep or
  restart dynos/containers; free VPS tiers are scarce and
  reclaim idle instances. A supervisor restart budget assumes a
  host that *mostly* stays up — on a host that sleeps hourly,
  the correct behaviour is the FAILED state and an operator,
  not an infinite loop.
* **Recovery limits after host failure:** if the host dies,
  in-flight segments are judged at next startup (valid partials
  promoted, corrupt ones discarded) and streams must be
  re-prepared; viewer-facing continuity across a host loss is
  not achievable at this tier and is not claimed.
* **No free hosting guarantees uninterrupted 24/7 streaming.**
  The portable design (env-configured units, stdlib-only
  tooling, no paid dependencies) means a paid or self-hosted
  runtime can be adopted later without rework.

## 7. Remaining issues & recommended fixes

1. **Supervisor single point of failure (#10)** — run it under
   a real init system (systemd) on the eventual host; on this
   VM there is nothing to register it with.
2. **Alert degradation trigger untested** — add a forced-failure
   test for `AlertService._loop` in a future phase.
3. **Stream stall detection latency (#8)** — if the host loop
   hitches badly, detection waits; an out-of-process progress
   file watcher would remove the coupling.
4. **Long soaks still owed** — a 6-hour supervised run on the
   eventual host is the gate for any "stable" claim beyond
   what 600 s here supports; 24 h+ remains unproven by design
   of this phase's environment.
5. **Adopted-process exit codes are unknowable** (a process the
   supervisor didn't spawn can't report its code) — cosmetic;
   detection and recovery are unaffected.
