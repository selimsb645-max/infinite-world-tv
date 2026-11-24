# Security

## Secrets

| Secret | Where it lives | Never |
|---|---|---|
| YouTube stream key | host environment only (systemd `EnvironmentFile`, mode 600) | in the repo, in logs, in the dashboard, in chat |
| Dashboard password / TOTP seed | host environment | committed, echoed |
| GitHub token | repository secret | printed |

Rules:
- `gitleaks` runs in CI on every push; a hit fails the build.
- Logs scrub `rtmp://`, `key=`, and anything matching a 4-part dash pattern.
- The stream key is rotatable from the dashboard without a restart (stop → rotate → start).

## Dashboard access

- Password + TOTP, HMAC-signed cookie (HttpOnly, Secure, SameSite=Lax), 12-hour expiry.
- Roles: `admin` (mutations) and `viewer` (read only).
- Every mutation requires a CSRF token and is written to an append-only audit log.
- Rate limit: 5 failed logins per 10 minutes per IP, then lockout.

## Runtime

- The streamer and renderer run as unprivileged users under systemd with `NoNewPrivileges`,
  `PrivateTmp`, and a read-only root where possible.
- The dashboard never shells out with user-supplied strings.
- Emergency shutdown is available without SSH (dashboard) and with SSH (systemd unit), so a
  compromised dashboard cannot lock the owner out of stopping the stream.
