# INFINITE WORLD TV — Phase 09 Testing Report

Reliability, fault recovery & long-run stability. All results
below were executed in this session on this VM (shared 1.5 vCPU,
Godot 4.3 headless, llvmpipe, no GPU). Nothing is claimed beyond
what ran.

## New suite — reliability (51 checks)

Runner: `GODOT=<godot> bash tests/run_reliability_tests.sh`
Output: `tests/reliability_output.txt` —
`RELIABILITY_DONE failures=0` (GDScript 24 + Python 27).

### GDScript half (`ReliabilityTest.tscn`)

* Storage partials: old orphan reclaimed (partials_deleted=1),
  fresh + protected partials kept, finalized segment untouched
  under caps, `headroom_ok` false under a 0.01 MB quota.
* Recovery windows: 3 attempts allowed, 4th `give_up`, budgets
  per-issue, replenishment after the window (injected clock),
  `reset()` intact.
* Stream log: in-memory entries capped at exactly 1,000 after
  1,200 events; file complete at 1,200 appended lines; after a
  planted ~9 MB bloat, one event triggers the bounded rewrite
  (file back to ≤1,000 lines); last line parses as JSON with the
  newest event.
* Unprepared `StreamManager.start_stream()` → `not_prepared`.
* AI faults: null-controller perception returns
  `available=false` without error; recovery with missing or
  partial perception returns `none`; normal path intact.
* Generation soak (deterministic, seeds 777001…778000):
  1,000 levels, **1,000 valid** on independent re-validation,
  **1,000 distinct** fingerprints, 3 candidate rejections
  absorbed by bounded retries, 0 fallbacks used,
  `fallback_validation_failures=0`, history size 250 (cap),
  static memory growth **+1.80 MB**.

### Python half (`tests/reliability_test.py`)

* Log rotation: 200 appends at a 4 KB cap → total ≤ 3 files,
  bounded size, current file intact.
* Supervisor vs dummy units: start ok; duplicate start refused
  (`already_running`); SIGKILL detected; state BACKOFF (no
  instant restart); crash snapshot file exists; backoff timing
  respected; restarted with a new pid, restart counted;
  graceful stop ok; intentional stop never restarted.
* Crash loop: exactly 4 spawns (1 + max_restarts=3), then
  FAILED; further ticks spawn nothing; start refused with
  `unit_failed_operator_reset_required`; `reset_unit` recovers.
* Missing binary: `spawn_failed` reported, no loop.
* Independence: crash-looping unit FAILED while the healthy
  unit kept its original pid and RUNNING state; status JSON
  written; `stop_all` clean.
* Lock: first supervisor acquires, second refused, re-acquirable
  after release. (This check caught a real bug — same-process
  instances shared a pid identity — fixed in
  `dashboard/supervisor.py` before the suite went green.)
* Adoption: a process started externally (dashboard-style
  pidfile) is adopted, not duplicated, and can be stopped.

## Stability run (600 s, executed)

Driver: `tests/stability_run.py` → `tests/stability_output.txt`,
`STABILITY_DONE failures=0`.

* Stack: supervisor + GameService + StreamService + dashboard
  backend (all headless, throwaway runtime dir), 60 samples.
* Injected: SIGKILL game @240 s → recovered (1 restart);
  SIGKILL stream @420 s → recovered (1 restart); dashboard
  untouched. Injected-fault recovery rate 2/2.
* End states all RUNNING. Dashboard HTTP ok in 59/60 samples.
* RSS end/peak MB: game 98.8/103.0, stream 87.1/87.2,
  dashboard 14.7/21.6 (warm-up rise, flat steady state).
* CPU avg/peak %: game 2.2/8.2, stream 1.3/4.2, dashboard
  0.1/1.3. Bridge FPS median 145 (menu scene, llvmpipe —
  liveness evidence only).
* Caveat: regression suites ran concurrently for roughly the
  first half — loaded-VM numbers.

## Regressions (re-run after all Phase 09 changes)

| Suite | Result |
|---|---|
| Smoke | 26/26 — `SMOKE_DONE failures=0` |
| Generation | 45/45 — `GEN_DONE failures=0` |
| Autopilot | 29/29 — `AUTOPILOT_DONE failures=0` |
| Asset | 237/237 — `ASSET_DONE failures=0` |
| Video | 84/84 — `VIDEO_DONE failures=0` |
| Stream | 51/51 — `STREAM_DONE failures=0` |
| Dashboard | 45/45 — `DASHBOARD_DONE failures=0` |

## Not executed

1 h / 6 h / 24 h / 7 d soaks (session limits — only 600 s ran);
real YouTube disconnect (no stream key, Phase 07 rule); real
disk-full (quota simulation instead); GPU/VRAM faults (no GPU);
real host-loss drill (cold-start paths unit-tested instead);
alert-service degradation trigger (implemented, not
force-tested). Full reasoning in `docs/PHASE09.md` §5–§7.
