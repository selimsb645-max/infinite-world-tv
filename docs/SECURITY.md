# Security Guide — INFINITE WORLD TV

Final security review performed in Phase 10 (2026-11-25).
**Scope note:** this is an internal review by the development
agent — code inspection, configuration scan and the project's
own security tests. It is *not* a professional security audit
and must not be represented as one.

## Method

- Grep scan of every tracked file for credential patterns
  (private keys, cloud/GitHub token formats, literal
  key/password assignments, RTMP URLs carrying keys).
- Verification that `.env` is untracked and gitignored, and
  that `.env.example` contains placeholders only.
- Inspection of every process-execution call site, the
  dashboard's auth/session/authorization code, the control
  endpoints, and the secret-redaction choke points.
- The project's executable proofs: stream suite (51 checks —
  redaction, authorization refusals, public-confirmation
  safeguard), dashboard suite (45 checks — auth, roles, rate
  limiting, audit, planted-secret redaction), integration
  suite (public start refused without confirmation, prepare
  spawns no process).

## Findings

No critical or high-severity issue was found. No code fix was
required in Phase 10. Details:

### Secrets management — PASS

- No hardcoded credentials anywhere in the tracked tree.
  The scan found no private keys, no real token formats, no
  literal secret assignments.
- `.env` is not tracked; `.gitignore` covers `*.env` /
  `.env*` with `!.env.example` as the only exception, and
  the example file contains placeholders only
  (`PASTE_YOUR_STREAM_KEY_HERE`, `GENERATE_A_LONG_RANDOM_TOKEN`).
- No `.log`, `.jsonl`, `.pem` or `.key` files are tracked.
- The fake keys used by tests (`FAKEKEY-…`, `IWT-E2E-FAKE-KEY`)
  appear only in test *sources* and docs describing the
  redaction tests — a deliberate fixture, not a credential —
  and in **no** test output or log artifact, which is exactly
  what the redaction proofs assert.
- The real stream key materialises in exactly one place:
  `StreamConfig.full_url()`, whose result is handed only to
  the ffmpeg process arguments. Every log line, status field
  and error in the streaming layer passes through
  `StreamConfig.redact()` (single choke point in
  `StreamManager.log_event`), and the dashboard applies a
  second redaction pass at its boundary.

### Authentication & authorization (dashboard) — PASS

- Tokens compared with `hmac.compare_digest` (constant time).
- Login exchanges a token for a session cookie set
  `HttpOnly; SameSite=Strict`. Sessions are server-side.
- Login is rate-limited (repeated failures → HTTP 429).
- Every sensitive endpoint checks the session role
  server-side (`_require`); viewer role gets 403 on controls
  and logs. Security does not rely on hidden buttons.
- Control actions are allowlisted twice: in
  `dashboard/server.py` (`_control` dispatches a fixed action
  set) and again in the GDScript bridges (unknown actions
  return `unknown_action`). Game command parameters are cast
  by the bridge (`seed` → int), so operator input cannot
  smuggle shell or code.
- Every control action is written to an audit log with the
  role and the result — never the token.
- The dashboard binds `127.0.0.1` by default.

### Process execution — PASS

- No `shell=True`, `os.system`, `eval` or string-built shell
  commands anywhere in `dashboard/` or the game code.
- All spawns are argv arrays: Python `subprocess.Popen([...])`
  (supervisor, process control) and Godot `OS.execute(path,
  PackedStringArray([...]))` (ffmpeg/ffprobe).
- The supervisor refuses duplicate instances via a lock and
  pid-checked pidfiles; the stream layer has its own
  pid-checked encoder lock.

### Streaming safeguards — PASS

- Prepare and broadcast are separate operations; prepare
  spawns nothing (asserted in the Phase 10 integration
  suite).
- Starting a **public** broadcast requires the admin token
  *and* a separate explicit `confirm_public` flag; without
  it the refusal is `public_confirmation_required`
  (re-verified end-to-end in Phase 10).
- Without a stream key in the environment, streaming is
  `NOT CONFIGURED` and start attempts fail validation —
  the safe default for an unconfigured service.

## Observations (not vulnerabilities; know them before deploying)

1. **The stream key is visible in the ffmpeg process list**
   to other processes running as the same OS user (it is an
   ffmpeg command-line argument — the standard RTMP auth
   mechanism). Run the stack under a dedicated user account
   on a multi-user host.
2. **Session cookie has no `Secure` flag** — correct for
   plain-HTTP localhost use. If the dashboard is reached
   through a network, terminate TLS at a reverse proxy (see
   `docs/DEPLOYMENT.md`); do not expose the built-in server
   directly to the internet.
3. **Test fixture tokens are committed in test sources.**
   They are fake values used against local test instances.
   Real deployments must set their own `IWT_ADMIN_TOKEN` /
   `IWT_VIEWER_TOKEN` via the environment — anyone who skips
   that step and exposes a dashboard running test tokens has
   effectively no auth. The deployment checklist calls this
   out explicitly.
4. **File-based IPC** between the dashboard and the Godot
   services (command/result JSON in the runtime dir) trusts
   the local filesystem: any local process that can write
   the runtime dir can issue game/stream commands, though
   stream start/stop still requires the admin token inside
   the stream service. Keep the runtime dir permissions
   restricted to the service user.

## Operator rules (unchanged since Phase 07)

- Stream keys come only from the environment / `.env`.
  Never commit them, never print them, never paste them
  into chats or tickets.
- If a key ever leaks: reset it immediately in YouTube
  Studio (Live Control Room → stream key → Reset).
- A public livestream is never launched without Selim's
  explicit approval at that moment.
