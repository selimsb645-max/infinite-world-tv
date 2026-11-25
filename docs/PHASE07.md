# Phase 07 — YouTube Live Streaming & 24/7 Broadcast Infrastructure

Status: **built and tested locally** (2026-11-24). Stream suite
**51/51 PASS** (`tests/stream_output.txt`, `STREAM_DONE failures=0`),
including real ffmpeg RTMP streaming processes verified end-to-end
against a **local** RTMP listener. Regressions clean: Phase 02
smoke 26/26, Phase 03 generation 45/45, Phase 04 autopilot 29/29,
Phase 05 asset 237/237, Phase 06 video 84/84.

**No YouTube livestream was started — public, private or unlisted.**
No real stream key exists in this project, and none was created or
used. Every process test ran against ffmpeg's own RTMP listener on
127.0.0.1 with an obvious fake key. What is proven and what is not
is stated plainly in "Honest limits" below.

## What was built

| Module | File | Responsibility |
|---|---|---|
| StreamConfig | `game/scripts/stream_config.gd` | All streaming settings on top of the Phase 06 `EncodingConfig` (which stays the single source of truth for resolution/fps/bitrates/preset): ingest base URL, visibility, keyframe interval (default 2 s), reconnect budget + exponential backoff, stall timeout, auto-recovery flag. Loads the stream key from the environment or a gitignored `.env`; validates everything before any process starts; `redact()` scrubs the key out of any string |
| StreamManager | `game/scripts/stream_manager.gd` | The streaming engine (a Node): prepare/start/stop/restart, exactly one ffmpeg child process, FLV-over-RTMP(S) command building (H.264 CBR, GOP = fps × keyframe interval, AAC 44.1 kHz), monitoring via ffmpeg's `-progress` report + zombie-safe `ps` liveness, bounded reconnect with backoff, output-stall detection, lock-file duplicate prevention across instances, graceful shutdown (SIGTERM → bounded wait → SIGKILL) |
| StreamHealthMonitor | `game/scripts/stream_health_monitor.gd` | Session bookkeeping and the dashboard snapshot: status, start time, uptime, target vs measured resolution/FPS/bitrate, dropped/duplicated frames, ffmpeg pid/aliveness, reconnect count, network interruptions, CPU % (from `/proc/stat`), RAM, last health check, last error, last recovery. Issue codes: PROCESS_DEAD, OUTPUT_STALLED, LOW_FPS, DROPPING_FRAMES |
| StreamAdmin | `game/scripts/stream_admin.gd` | Backend admin controls: prepare, start, stop, restart, health check, view logs, enable/disable auto-recovery, configure quality (1080p/720p). Sensitive actions require the `IWT_ADMIN_TOKEN`; starting a **public** broadcast additionally requires a separate `confirm_public` flag that defaults to false at every layer |

Supporting files: `.env.example` (placeholders only), `.gitignore`
now exempts `.env.example` while `.env`/`*.env`/`secrets/` stay
ignored (verified with `git check-ignore`), `tests/run_stream_tests.sh`.

## Architecture

Responsibilities stay separated exactly as the phase spec requires:

- **GitHub** — source control, history, review. Not a server (see
  the feasibility report).
- **Game Engine** (Phases 02–05) — gameplay, unchanged.
- **Rendering Engine** (Phase 06) — capture + mix + encode. The
  streaming engine consumes its output interface: a PNG frame
  sequence at the encoder resolution (what `GameCaptureManager`
  writes) plus a mixed WAV (what `AudioMixer` renders), or a
  finished file in file mode.
- **Streaming Engine** (Phase 07) — one ffmpeg process, RTMP(S)
  transmission, reconnect/recovery.
- **Monitoring Engine** (Phase 07) — `StreamHealthMonitor` +
  structured, timestamped, severity-tagged, **redacted** logs
  (in memory, optionally mirrored to a JSON-lines file).
- **Dashboard** — backend only in this phase: `StreamAdmin` +
  the secret-free `check_health()` snapshot are the contract a
  future UI calls. The snapshot never contains the ingest key —
  it is not stored in the health monitor at all.

Preparation is separate from broadcasting: `prepare_stream()`
validates and stores configuration and spawns nothing (tested).
`start_stream()` is the only spawn path in the codebase.

## Secure credential setup

Rules enforced by construction, and proven by tests:

- The stream key is read **only** from the `IWT_YOUTUBE_STREAM_KEY`
  environment variable or a gitignored `.env` file
  (`StreamConfig.apply_environment()` / `load_env_file()`).
  Environment wins over the file. Nothing is hardcoded; the repo
  contains no real key (the test key is the literal string
  `FAKEKEY-test-7f3d9a-NOT-REAL`).
- The key materialises in exactly one place: the spawned ffmpeg
  process's argument list, in memory (`StreamConfig.full_url()`).
- Every log entry passes through `StreamConfig.redact()` at the
  single logging choke point; status snapshots and error strings
  are built from redacted summaries (`key=set`/`key=missing`,
  ingest shown as `…/live2/***`). A dedicated test concatenates
  all logs, statuses, summaries and the on-disk log file from a
  full streaming session and asserts the fake key appears nowhere
  — while asserting the process arguments *do* carry it, so the
  check cannot pass vacuously.
- Validation errors name the missing variable
  (`missing_credentials:IWT_YOUTUBE_STREAM_KEY`), never a value.
- If a key ever leaks: reset it in YouTube Studio (Live Control
  Room → the stream key's Reset) — the old key dies immediately.

Setup: `cp .env.example .env`, fill in your key, never commit the
result. `.env.example` documents each variable.

## YouTube setup instructions (operator, manual)

The channel plan is: new channel, **manual operation until 50
subscribers**, automation afterwards. The system supports that —
nothing auto-starts; an operator (or later, a scheduler the owner
approves) calls the admin controls.

1. Create the channel and **verify it** (phone verification) in
   YouTube Studio.
2. Request live access: Studio → Create → Go live. First-time
   enablement can take **up to 24 hours**. Note the eligibility
   rules in the policy section below — in particular the operator
   must be **16 or older**.
3. In the Live Control Room, open the **Stream** tab and copy the
   stream key. Treat it like a password (see above).
4. Put the key in the environment of the machine that will run
   the game + streaming engine:
   `export IWT_YOUTUBE_STREAM_KEY=…` (or a local `.env`).
   Optionally set `IWT_STREAM_VISIBILITY` (default `private`) and
   `IWT_ADMIN_TOKEN` (required for admin start/stop).
5. Prepare with `StreamAdmin.prepare_stream(...)`, confirm the
   returned validation is clean, check `check_health()`.
6. First real test: keep visibility **private**, start the stream
   from the admin controls, watch it in the Live Control Room,
   verify picture + audio, stop it. Only after a private test
   passes should an unlisted, then public, broadcast be
   considered — and public always needs the separate confirmation
   flag in the admin call.
7. Ingest: the default base is YouTube's primary RTMPS endpoint
   (`rtmps://a.rtmps.youtube.com/live2`) as shown in the Live
   Control Room; YouTube recommends RTMPS. The backup ingest shown
   in Studio can be substituted via `IWT_RTMP_INGEST_URL`.

## Encoder settings vs YouTube's official guidance

Checked against YouTube Help on 2026-11-24
([encoder settings, answer/2853702](https://support.google.com/youtube/answer/2853702)):

| Setting | YouTube guidance | This project |
|---|---|---|
| Protocol | RTMP/RTMPS, **RTMPS recommended** | RTMPS default |
| Video codec | H.264 (also H.265/AV1) | H.264 (libx264) |
| Bitrate mode | CBR | CBR (`-b:v` == `-maxrate`) |
| Keyframe interval | **2 s recommended, never > 4 s** | 2 s default; validation rejects > 4 s |
| 1080p30 H.264 bitrate | ≈10 Mbps recommended (range 5–14) | Phase 06 preset: 8000 kbps — inside range |
| 720p30 H.264 bitrate | ≈4 Mbps | Phase 06 preset: 4000 kbps |
| 1080p60 / 720p60 | ≈12 / ≈6 Mbps | presets scale (12000 / 6000 kbps) |
| Audio | AAC, 128 kbps stereo recommended | AAC 44.1 kHz, 160 kbps default (configurable) |
| Frame rate | up to 60 fps | 24/30/60 per EncodingConfig |

## Monitoring & recovery behaviour

- ffmpeg writes a `-progress` report every 0.5 s; the manager
  polls it and the process liveness every frame (and on demand
  via `poll()`). A child that exited but was not reaped is a
  zombie — liveness uses `ps -o stat=` because `kill -0` and
  `/proc` reads both lie for zombies (this bug was found and
  fixed during testing; see the testing report).
- **Unexpected exit** (crash, killed encoder, remote end drops):
  counted as a broadcast interruption if data was flowing, logged
  at error level, and — if auto-recovery is on — restarted after
  `backoff_delay(attempt)` = base × 2^(attempt−1), capped
  (defaults 2 s → 60 s, max 5 attempts). Budget spent → state
  FAILED, nothing restarts until an operator acts. **There is no
  code path that retries forever.**
- **Output stall** (process alive, no progress for
  `stall_timeout_sec`, default 10 s): counted as a network
  interruption, the encoder is killed and the same bounded
  reconnect path runs.
- **Graceful stop**: SIGTERM, up to 2.5 s to exit, then SIGKILL;
  the lock file is removed and a pending reconnect is cancelled.
- **Duplicates**: start refuses while streaming/recovering, and a
  pid-checked lock file refuses a second manager on the same
  runtime directory.

## Free infrastructure feasibility report (honest)

**No free infrastructure guarantees uninterrupted 24/7 streaming,
and this report does not claim otherwise.** What each candidate
can actually do:

**This VM (current dev machine).** 4 shared vCPUs, ≈8 GB RAM,
≈138 GB free disk, **no GPU**. Measured in Phase 06: the game
itself renders at ≈5 fps at 720p under llvmpipe software GL —
so this machine **cannot originate a real-time 720p30 (let alone
1080p) stream today**; the pipeline mechanics are proven, the
frame rate is a hardware limit. A bare TCP connection to
YouTube's ingest port (1935) succeeded from this shell, but no
RTMP handshake or publish was attempted, and this VM is an
ephemeral dev environment, not a host. Verdict: development and
short supervised tests only.

**GitHub Actions.** Free for public repositories, but it is a CI
system, not a streaming server: GitHub-hosted jobs are capped at
**6 hours of execution per job**, runners are ephemeral (no
persistent disk, no inbound access, no uptime promise), and
long-running non-CI workloads sit outside what the platform is
for. This matches the owner's own plan — **~6-hour Actions
sessions with 30–60 minute breaks** — and the architecture
supports exactly that (a workflow starts the stack, streams one
session, stops). It is *not* 24/7: between sessions the channel
is offline, a failed job start means no stream, and sustained
real-time encoding on a shared 2–4 vCPU runner at 1080p is
unproven. Verdict: feasible for scheduled sessions at 720p,
with gaps by design.

**Other free tiers (as of 2026-11-24).** Oracle Cloud's Always
Free Ampere tier is the only mainstream offer with meaningful
always-on compute, but signup requires a payment card, capacity
in many regions is scarce, and idle instances can be reclaimed.
Google Cloud's free e2-micro (1 vCPU / 1 GB, limited regions,
tight egress rules) is too weak to encode 720p in real time.
Render/Fly.io/Railway-style free tiers have moved to trials,
sleep-on-idle, or paid-only for persistent processes — a sleeping
process cannot hold an RTMP stream. Verdict: no dependable free
24/7 host exists for this workload; if one appears, the portable
design (env-configured, no platform SDKs, plain ffmpeg + Godot)
moves without a rewrite.

**Bandwidth reality check.** Streaming is continuous upload:
1080p30 at 10 Mbps ≈ **4.5 GB/hour ≈ 108 GB/day ≈ 3.2 TB/month**;
720p30 at 4 Mbps ≈ 1.8 GB/hour (≈11 GB per 6-hour session,
≈1.3 TB/month at 24/7). Any free tier's transfer allowance is
exhausted by orders of magnitude; the operator's own connection
must sustain the bitrate with headroom for the whole session.

**Conclusion.** Realistic free operation = scheduled sessions
(GitHub Actions ~6 h blocks, or a machine the owner controls)
at 720p, started manually — which is precisely the channel plan
(manual until 50 subscribers). True 24/7 will require a
persistent host with a GPU or a strong CPU and unmetered upload;
that is a later, likely paid, decision for the owner. This phase
builds everything up to that decision and nothing depends on it.

## YouTube policy & audience safety

From YouTube Help, checked 2026-11-24
([get started, answer/2474026](https://support.google.com/youtube/answer/2474026);
[restrictions, answer/2853834](https://support.google.com/youtube/answer/2853834);
[policy updates, answer/10008196](https://support.google.com/youtube/answer/10008196)):

- **Eligibility.** Live streaming requires a **verified channel**
  and **no live-streaming restrictions in the past 90 days**.
  First-time enablement can take up to 24 hours.
- **Minimum age.** Since **22 July 2025** the minimum age to live
  stream is **16**. Streams violating this are taken down and the
  account may temporarily lose live access. Creators aged 13–15
  may only take part with an adult **visibly present and
  co-creating**; an under-16 creator can give an adult access as
  editor/manager/owner, and that adult starts the stream from the
  Live Control Room and stays visibly present. **This project
  never bypasses these rules**: the operator of this system must
  personally meet the age requirement, or an eligible adult must
  operate it. (The game itself shows no people at all — but the
  rule governs who may run the stream, so it is recorded here as
  a hard precondition.)
- **Subscribers.** The **50-subscriber minimum applies to mobile
  live streaming only**. Streaming with an encoder (this system)
  has **no subscriber minimum** — so the channel's "manual until
  50 subscribers" plan is a choice, not a platform gate.
- **Made for Kids.** The audience setting is the creator's legal
  declaration about whether content is directed to children
  (COPPA factors: subject matter, characters, language, activities
  appealing to children). INFINITE WORLD TV is an original,
  family-friendly game broadcast aimed at a general gaming
  audience — no child performers, no children's characters or
  nursery content — so the honest setting is **not made for
  kids**, and the operator must set it deliberately rather than
  by default. Consequences if a stream *is* set made for kids:
  **live chat, Super Chat, comments on archives and reminder
  notifications are disabled** and personalized ads are off —
  which would remove the chat interaction a 24/7 channel expects.
  YouTube can also reclassify content itself; the setting must
  match the content, not the desired features.
- **Other limits.** There is a **daily limit on creating live
  streams** (wait 24 hours if hit) — session-based operation
  should reuse one scheduled stream per session rather than
  creating many. All content must follow the Community Guidelines
  and Terms of Service; this system only pushes an RTMP feed from
  an operator-started process — it does not automate YouTube
  account actions, viewership, or engagement of any kind.
- All gameplay, visuals and audio are original (Phases 02–05),
  so the broadcast carries no third-party copyright exposure from
  the game itself.

## Tests

Suite: `godot --headless --path game res://tests/StreamTest.tscn`
or `GODOT=godot bash tests/run_stream_tests.sh` →
`tests/stream_output.txt`, **51/51 PASS, `STREAM_DONE failures=0`**.
Full detail in `tests/TESTING_REPORT_PHASE07.md`. Highlights:

- Config validation (incl. keyframe > 4 s rejected), missing
  credentials flagged by variable name, env-var and `.env`
  loading, backoff sequence 2/4/8/16 capped at 60.
- Redaction: a fake key streamed a real session, then every log,
  status, summary and the on-disk log file were searched — key
  absent everywhere except the process arguments themselves.
- Admin: wrong/absent token refused on every sensitive action;
  prepare spawns nothing; start without credentials refused.
- Public safeguard: public start refused without the confirmation
  flag (no process, still PREPARED); with the flag it starts —
  against the **local** listener only.
- Real processes: ffmpeg streamed the Phase 06-style frame
  sequence + tone to ffmpeg's RTMP listener; the listener's
  recording probes as H.264 + AAC. Duplicate start refused.
  Quality change refused mid-stream. Graceful stop verified
  (process gone, lock released).
- Crash: encoder killed with SIGKILL → detected, reconnected to a
  fresh listener within budget, second recording is valid H.264.
- Network: listener killed mid-stream → interruption counted,
  reconnect attempted.
- Limits: dead-port target with max 2 attempts → exactly 2
  attempts, state FAILED, further `poll()` calls change nothing.
  Auto-recovery off → first failure is final.

**Not executed, honestly:** any test against YouTube itself
(private/unlisted test stream, RTMPS handshake, Live Control Room
verification) — no stream key exists and creating/using one was
outside this phase's authority; a 6-hour Actions stability run
and real-time 1080p streaming — beyond this VM's hardware and
session limits. These remain for the owner's supervised first
private test (see setup instructions).

## Honest limits

- **The RTMP publish path is proven against ffmpeg's own RTMP
  server on loopback, not against YouTube's ingest.** The command
  follows YouTube's documented encoder guidance and the ingest
  URL format shown in the Live Control Room, but YouTube-side
  behaviour (auth quirks, ingest acceptance, Control Room
  reporting) is unverified until the owner's first private test.
- **This VM cannot originate a real-time stream**: ≈5 fps game
  rendering under llvmpipe (Phase 06 measurement). The streaming
  engine moves whatever frames the renderer produces; on hardware
  that renders 720p30+, the same code streams it.
- Live frame transport inherits Phase 06's PNG-sequence design:
  the manager streams a frames directory (or a file with
  `-stream_loop`); a zero-copy pipe from capture to encoder is a
  possible later optimization, not implemented.
- ffmpeg's own stderr is not captured (Godot child processes have
  no readable pipes); monitoring relies on the `-progress` report,
  exit detection and the recorded FLV/ingest side — sufficient for
  every recovery decision the manager makes.
- CPU % is whole-machine (from `/proc/stat`), RAM is the Godot
  process's static memory; per-process ffmpeg CPU is not broken
  out.
- The admin layer is a backend API in GDScript — there is no web
  dashboard UI in this phase, and token comparison is a plain
  equality check suitable for a local operator tool, not a
  public-facing service.
