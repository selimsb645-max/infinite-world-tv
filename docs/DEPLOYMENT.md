# Deployment Guide — INFINITE WORLD TV

How the complete system is deployed for a controlled run, which
parts need a persistent machine, and the exact checklist for the
first (private) YouTube test. Everything here matches the code as
of Phase 10. Free and open-source tools only; no paid service is
a mandatory dependency anywhere in this design.

## Deployment architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Persistent machine (ONE host runs everything below)          │
│                                                              │
│  dashboard/supervisor.py  ── owns/restarts all units         │
│    ├─ game unit      Godot GameService.tscn                  │
│    │                 (game + AI autopilot + Phase 06         │
│    │                  renderer, under Xvfb or a display)     │
│    ├─ stream unit    Godot StreamService.tscn                │
│    │                 (Phase 07 StreamManager/Admin;          │
│    │                  ffmpeg RTMP(S) process when live)      │
│    └─ dashboard unit dashboard/server.py (127.0.0.1:8787*)   │
│                                                              │
│  Persistent storage: recordings/ (capped), runtime dir       │
│  (status JSON, logs — rotated), .env (secrets, gitignored)   │
└──────────────────────────────────────────────────────────────┘
        ▲ git pull / file copy                │ RTMPS (when live)
┌───────┴───────────────┐          ┌──────────┴───────────────┐
│ Source repository     │          │ YouTube Live ingest      │
│ (GitHub) — code + CI  │          │ (owner's channel + key)  │
└───────────────────────┘          └──────────────────────────┘
```

Component responsibilities and persistence needs:

| Component | Where it lives | Needs a persistent machine? |
|---|---|---|
| Source code repository | GitHub (`selimsb645-max/infinite-world-tv`) | No — version control + CI only |
| Game runtime | Godot `GameService.tscn` under the supervisor | **Yes** — must run continuously |
| Rendering runtime | Inside the game process (Phase 06 `VideoRenderer`) | **Yes** — same host as the game |
| Streaming runtime | Godot `StreamService.tscn` + ffmpeg child | **Yes** — same host |
| Monitoring service | Supervisor + health monitors + dashboard alert service | **Yes** — same host |
| Dashboard backend | `dashboard/server.py` (Python 3 stdlib) | **Yes** — same host; localhost by default |
| Dashboard frontend | Static files served by the backend | No separate host |
| Persistent storage | `recordings/`, dashboard runtime dir, `.env` | **Yes** — same host's disk |

\* Port is configurable (`IWT_DASHBOARD_PORT`); see
`docs/RUNNING.md` and `dashboard/server.py` for all variables.

**GitHub Actions is CI/CD only.** It runs the test suites on
push. It is *not* a streaming server: jobs are time-capped
(6 h), ephemeral, and have no persistent disk. The realistic
free pattern (see `docs/PHASE07.md`) is supervised ~6-hour
sessions with breaks on whatever host is available — started by
a human, monitored by the dashboard — not a guaranteed 24/7
broadcast.

## Host requirements (from Phase 10 measurements)

Measured on the development VM (no GPU, llvmpipe, ~1.5 shared
CPU): the game renders ≈3–5 fps at 720p — **not real-time**.
A host that originates a watchable stream needs, realistically:

- A GPU (or a far stronger CPU) so Godot renders 720p at a
  stable 30 fps — this is the single hard requirement the
  current VM does not meet.
- ≥2 CPU cores and ≥4 GB RAM for game + encoder + services
  (measured service footprint is small: game ≈50–100 MB RSS,
  stream service ≈45–90 MB, dashboard ≈15–22 MB; encoding is
  the CPU-hungry part).
- Disk: recordings are capped by the Phase 06 storage policy;
  budget a few GB plus rotated logs.
- Network: sustained upload ≥6 Mbps for 720p30, ≥12 Mbps for
  1080p30 (1080p30 ≈ 3.2 TB/month of transfer — see
  `docs/PHASE07.md` for the full bandwidth math and why free
  tiers with transfer caps cannot carry a month of 1080p).

The stack is portable: it is a Godot project, three Python
stdlib files' worth of backend, ffmpeg, and environment
variables. Moving hosts = copy the repo, install Godot 4.3 +
ffmpeg, recreate `.env`. Nothing is tied to this VM.

## Configuration

All configuration is environment variables (or a gitignored
`.env`); see `.env.example` for the streaming secrets template
and `docs/PHASE07.md` §secure setup. Rules that hold in every
deployment:

- No stream key or token in code, in git, or in any log.
- Streaming reports **NOT CONFIGURED** until
  `IWT_YOUTUBE_STREAM_KEY` is set — that is the safe default.
- The dashboard binds `127.0.0.1` unless `IWT_DASHBOARD_HOST`
  is deliberately changed. To reach it from another device,
  put a TLS-terminating reverse proxy in front of it (the
  built-in server is plain HTTP for localhost use) or use an
  SSH tunnel. Do not expose it raw to the internet.
- A **public** broadcast additionally requires the explicit
  `confirm_public` flag at start time — configuration alone
  can never make a stream public.

## Controlled deployment checklist

Steps marked **[OWNER]** can only be done by Selim himself
(accounts, keys, approvals). Everything else is Muse's job.

1. [ ] Pick the host (must meet the rendering requirement
   above) and install Godot 4.3, FFmpeg, Python 3, Xvfb if
   headless.
2. [ ] Clone/copy the repository; confirm `git status` clean.
3. [ ] Run the full test suite on the host:
   `bash tests/run_integration_tests.sh` plus the per-phase
   runners in `docs/RUNNING.md`. Expect every `*_DONE
   failures=0`.
4. [ ] Validate rendering output: the integration suite's
   leg 1 already produces and ffprobe-validates a real MP4;
   check `recordings/run_e2e/` on the host.
5. [ ] Validate FFmpeg: `ffmpeg -version`, and confirm the
   stream suite passes against the local listener.
6. [ ] **[OWNER]** Create the YouTube channel (or use an
   existing one), complete channel verification, and confirm
   the operator meets YouTube's live-streaming eligibility —
   including the minimum-age rule (16+; see `docs/PHASE07.md`).
7. [ ] **[OWNER]** In YouTube Studio → Go Live, create a
   **private** (or unlisted) test stream and copy its stream
   key. Set the content's audience designation deliberately
   (Made for Kids determination is documented in
   `docs/PHASE07.md`).
8. [ ] **[OWNER]** Put the key in the host's environment /
   `.env` (`IWT_YOUTUBE_STREAM_KEY`), set
   `IWT_STREAM_VISIBILITY=private`, and choose an
   `IWT_ADMIN_TOKEN`. Never paste the key into chat, code or
   a commit. (Muse can guide; the key itself is entered by
   the owner on the host.)
9. [ ] Start the stack under the supervisor
   (`dashboard/supervisor.py`, see `docs/RUNNING.md` Phase 09
   section) and open the dashboard: game should read RUNNING
   (autonomous), streaming should read configured/idle — not
   NOT CONFIGURED any more.
10. [ ] From the dashboard, **Prepare** the stream, verify
    the health snapshot, then **Start** the private stream.
    Watch the dashboard streaming section (bitrate, FPS,
    reconnect count) and YouTube's Live Control Room.
11. [ ] Run it as a controlled test (suggested first run:
    15–30 minutes). Deliberately stop/start once and confirm
    the bounded reconnect behaviour and the dashboard alerts.
12. [ ] Review the logs (dashboard Logs view / runtime dir):
    no secrets, no unexplained errors; check the audit log
    records every control action taken.
13. [ ] Produce the deployment readiness update: append the
    result (durations actually run, issues seen) to
    `docs/PHASE10.md`'s readiness section or a dated addendum.
14. [ ] **[OWNER]** Only after a successful private test, and
    only with Selim's explicit approval at that moment,
    consider an unlisted or public stream. A public start
    will still demand the separate confirmation flag.

## What "deployed" does not mean yet

- It does not mean 24/7. No free host guarantees that, and
  the long-duration soaks (1 h / 6 h / 24 h) have not been
  run — see `docs/PHASE09.md` and `docs/PHASE10.md`.
- It does not mean public. Step 14 is a separate, explicit
  human decision, every time the setup changes materially.
