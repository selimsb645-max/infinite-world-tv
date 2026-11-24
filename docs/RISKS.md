# Risks, ranked

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| 1 | No always-on host approved | stream never launches | decide P0; Oracle ARM free tier first, VPS fallback |
| 2 | YouTube denies live access / channel restrictions | no broadcast | apply early, keep 24h buffer of segments ready, test with unlisted stream first |
| 3 | Software rendering too slow for 1080p60 | render backlog | render at 1080p30, use Movie Maker mode (speed is decoupled from playback) |
| 4 | Content ID claim on audio | stream muted/blocked | synthesise all audio in-repo; no sample libraries |
| 5 | Procedural levels look repetitive | viewers leave | anti-repetition rules + themed segment catalogue; measure similarity in CI |
| 6 | Autonomous player stalls mid-level | black screen on stream | recovery + checkpoint respawn + stream-side "safe loop" fallback segment |
| 7 | Memory leak in long sessions | crash after hours | 6-hour soak in P2/P5, per-level node cleanup assertions |
| 8 | Secrets leaked (stream key) | hijacked stream | key only in host env, never in repo/logs, rotation runbook, gitleaks in CI |
| 9 | Asset originality dispute | channel strike | provenance records, scripted assets only, review checklist per phase |
| 10 | Scope creep (ML player, multi-platform) | project never ships | non-goals list in ROADMAP is binding for v1 |

## Kill criteria

If after P5 the measured 24h stream has more than 3 unrecovered drops, or the render backlog
exceeds 4 hours of buffer, the launch is postponed until the numbers improve. Shipping a
flaky 24/7 channel damages the channel more than a later launch.
