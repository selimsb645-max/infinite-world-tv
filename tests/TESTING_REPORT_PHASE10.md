# Testing Report — Phase 10 (Final Integration)

All suites executed fresh on 2026-11-25 on the development
VM (no GPU, llvmpipe, Godot 4.3, FFmpeg 8.1.2). Full
analysis in `docs/PHASE10.md`.

| Suite | Checks | Result |
|---|---|---|
| Smoke | 26 | PASS 26/26 — `SMOKE_DONE failures=0` |
| Generation | 45 | PASS 45/45 — `GEN_DONE failures=0` |
| Autopilot | 29 | PASS 29/29 — `AUTOPILOT_DONE failures=0` (6/6 levels, 886 decisions) |
| Asset | 237 | PASS 237/237 — `ASSET_DONE failures=0` |
| Video | 84 | PASS 84/84 — `VIDEO_DONE failures=0` (sync 0.000 s; 48 valid segments in run C) |
| Stream | 51 | PASS 51/51 — `STREAM_DONE failures=0` |
| Dashboard | 45 | PASS 45/45 — `DASHBOARD_DONE failures=0` |
| Reliability | 51 | PASS 51/51 — `RELIABILITY_DONE failures=0` (1,000-level soak 1000/1000, +1.80 MB) |
| Stability | 600 s | PASS — `STABILITY_DONE failures=0`; 60 samples; SIGKILLs injected into game + stream, 2/2 recovered; dashboard HTTP 59/60 |
| Integration (new) | 38 | PASS 38/38 — `INTEGRATION_DONE failures=0` |

**Total: 606 checks, 0 failed, 0 skipped**, plus the
600 s stability run.

New in this phase — `tests/run_integration_tests.sh`
(leg 1: `game/tests/IntegrationTest.tscn`, in-engine chain
under Xvfb, 23 checks; leg 2: `tests/integration_test.py`,
supervised production topology + dashboard + SIGKILL
recovery, 15 checks) → `tests/integration_output.txt`.

Development note: leg 2's first run failed 10 checks
because the driver did not wait for the dashboard's HTTP
listener after the supervisor reported the unit RUNNING;
fixed by polling for real reachability (the same
distinction the dashboard itself makes between a process
existing and a service being fresh). Leg 1's first run
exposed two bugs in the new test's own expectations
(result-dict seed location; a `StreamConfig` method name).
All three bugs were in the new test code; no production
code changed in Phase 10.

Not executed: YouTube-side tests (no channel/key), 1 h+
soaks, real-time streaming rates (hardware ≈4 fps), GPU
faults, physical-device mobile check, TLS exposure.
Reasons and readiness consequences: `docs/PHASE10.md` §7–9.
