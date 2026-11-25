#!/usr/bin/env python3
"""Phase 08 — Central Admin Dashboard backend.

Python 3 standard library only (http.server). No pip installs, no
framework, no CDN. Serves a static frontend plus a JSON API whose
every value comes from the real system (see status_service.py).

Configuration (environment):
  IWT_DASHBOARD_HOST   bind address, default 127.0.0.1 (localhost
                       only — exposing beyond it is the operator's
                       job via a TLS reverse proxy, see PHASE08.md)
  IWT_DASHBOARD_PORT   default 8787
  IWT_ADMIN_TOKEN      admin credential (SECRET) — full control
  IWT_VIEWER_TOKEN     optional read-only credential (SECRET)
  IWT_GODOT_BIN        Godot 4 binary (default: `godot` from PATH)
  IWT_DASHBOARD_RUNTIME  runtime dir (default dashboard/runtime)
  IWT_RECORDINGS_DIR   Phase 06 recordings (default <repo>/recordings)
  IWT_GODOT_LOG        engine log path (default app_userdata logs)
  IWT_GAME_DISPLAY_MODE  auto | headless | windowed (default auto)
  IWT_ENV_FILE, IWT_YOUTUBE_STREAM_KEY, IWT_STREAM_* — consumed by
                       the stream service process, passed through.

Security model:
  * Login exchanges a token for an HttpOnly session cookie.
    Tokens are compared in constant time and never logged, stored
    on disk, or returned by any endpoint.
  * Roles: admin (status + logs + controls) and viewer (status +
    alerts only). Authorization is checked server-side on EVERY
    sensitive endpoint — the frontend merely mirrors it.
  * Login is rate limited per client IP (5 failures / 5 minutes
    lock the login endpoint for that IP until the window passes).
  * Every administrative action is written to audit.jsonl with the
    actor's ROLE (never the token) and the actual result.
"""
import hmac
import json
import os
import secrets
import shutil
import sys
import threading
import time
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from alert_service import AlertService          # noqa: E402
from log_service import LogService              # noqa: E402
from process_control import ProcessControl      # noqa: E402
from redact import redact, redact_obj           # noqa: E402
from status_service import StatusService        # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(HERE)
SESSION_TTL = 12 * 3600
LOGIN_MAX_FAILURES = 5
LOGIN_WINDOW = 300


class Config:
    def __init__(self):
        self.started_at = time.time()
        self.host = os.environ.get("IWT_DASHBOARD_HOST", "127.0.0.1")
        self.port = int(os.environ.get("IWT_DASHBOARD_PORT", "8787"))
        self.admin_token = os.environ.get("IWT_ADMIN_TOKEN", "")
        self.viewer_token = os.environ.get("IWT_VIEWER_TOKEN", "")
        self.godot_bin = (os.environ.get("IWT_GODOT_BIN", "")
                          or shutil.which("godot") or "")
        self.game_dir = os.path.join(PROJECT_ROOT, "game")
        self.project_root = PROJECT_ROOT
        self.runtime_dir = os.environ.get(
            "IWT_DASHBOARD_RUNTIME", os.path.join(HERE, "runtime"))
        self.game_rt_dir = os.path.join(self.runtime_dir, "game")
        self.stream_rt_dir = os.path.join(self.runtime_dir, "stream")
        self.game_pidfile = os.path.join(self.runtime_dir, "game.pid")
        self.stream_pidfile = os.path.join(self.runtime_dir, "stream.pid")
        self.game_stop_marker = os.path.join(self.runtime_dir,
                                             "game.stop_requested")
        self.game_status_path = os.path.join(self.game_rt_dir,
                                             "game_status.json")
        self.stream_status_path = os.path.join(self.stream_rt_dir,
                                               "stream_status.json")
        self.stream_log_path = os.path.join(self.stream_rt_dir,
                                            "stream_log.jsonl")
        self.dashboard_log_path = os.path.join(self.runtime_dir,
                                               "dashboard_log.jsonl")
        self.audit_log_path = os.path.join(self.runtime_dir, "audit.jsonl")
        self.alerts_log_path = os.path.join(self.runtime_dir, "alerts.jsonl")
        self.health_check_path = os.path.join(self.runtime_dir,
                                              "health_check.json")
        self.recordings_dir = os.environ.get(
            "IWT_RECORDINGS_DIR", os.path.join(PROJECT_ROOT, "recordings"))
        self.godot_log_path = os.environ.get(
            "IWT_GODOT_LOG",
            os.path.expanduser(
                "~/.local/share/godot/app_userdata/INFINITE WORLD TV"
                "/logs/godot.log"))
        self.game_display_mode = os.environ.get("IWT_GAME_DISPLAY_MODE",
                                                "auto")
        for path in (self.runtime_dir, self.game_rt_dir, self.stream_rt_dir):
            os.makedirs(path, exist_ok=True)


class Dashboard:
    def __init__(self, cfg):
        self.cfg = cfg
        self.control = ProcessControl(cfg)
        self.status = StatusService(cfg, self.control)
        self.logs = LogService(cfg)
        self.alerts = AlertService(cfg, self.status, self.control)
        self.sessions = {}
        self.sessions_lock = threading.Lock()
        self.login_failures = {}

    # -- logging / audit ---------------------------------------------------

    def log(self, level, message):
        entry = {"ts": time.time(), "level": level, "module": "dashboard",
                 "message": redact(message)}
        try:
            with open(self.cfg.dashboard_log_path, "a") as handle:
                handle.write(json.dumps(entry) + "\n")
        except OSError:
            pass

    def audit(self, role, action, result):
        entry = {"ts": time.time(), "level": "info", "module": "audit",
                 "message": "%s by %s -> %s" % (
                     action, role,
                     "ok" if result.get("ok") else
                     "error:%s" % result.get("error", "unknown")),
                 "action": action, "actor": role,
                 "ok": bool(result.get("ok"))}
        try:
            with open(self.cfg.audit_log_path, "a") as handle:
                handle.write(json.dumps(redact_obj(entry)) + "\n")
        except OSError:
            pass

    # -- sessions ------------------------------------------------------------

    def role_for_token(self, token):
        if not token:
            return None
        if self.cfg.admin_token and hmac.compare_digest(
                token, self.cfg.admin_token):
            return "admin"
        if self.cfg.viewer_token and hmac.compare_digest(
                token, self.cfg.viewer_token):
            return "viewer"
        return None

    def create_session(self, role):
        session_id = secrets.token_hex(24)
        with self.sessions_lock:
            self.sessions[session_id] = (role, time.time() + SESSION_TTL)
        return session_id

    def session_role(self, session_id):
        if not session_id:
            return None
        with self.sessions_lock:
            record = self.sessions.get(session_id)
            if record is None:
                return None
            role, expires = record
            if expires < time.time():
                del self.sessions[session_id]
                return None
            return role

    def drop_session(self, session_id):
        with self.sessions_lock:
            self.sessions.pop(session_id, None)

    # -- login rate limiting ---------------------------------------------------

    def login_locked(self, ip):
        now = time.time()
        failures = [t for t in self.login_failures.get(ip, [])
                    if now - t < LOGIN_WINDOW]
        self.login_failures[ip] = failures
        return len(failures) >= LOGIN_MAX_FAILURES

    def note_login_failure(self, ip):
        self.login_failures.setdefault(ip, []).append(time.time())


CFG = Config()
APP = Dashboard(CFG)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "IWT-Dashboard/1.0"

    # -- plumbing -----------------------------------------------------------

    def log_message(self, fmt, *args):  # keep stdout clean of tokens
        pass

    def _send(self, code, body, content_type="application/json",
              extra_headers=None):
        if isinstance(body, (dict, list)):
            payload = json.dumps(redact_obj(body)).encode()
        elif isinstance(body, str):
            payload = redact(body).encode()
        else:
            payload = body
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("X-Content-Type-Options", "nosniff")
        for key, value in (extra_headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(payload)

    def _json_body(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return {}
        if length <= 0 or length > 65536:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return {}

    def _session_role(self):
        jar = cookies.SimpleCookie(self.headers.get("Cookie", ""))
        morsel = jar.get("iwt_session")
        return APP.session_role(morsel.value if morsel else None)

    def _require(self, roles):
        role = self._session_role()
        if role is None:
            self._send(401, {"ok": False, "error": "unauthorized"})
            return None
        if role not in roles:
            self._send(403, {"ok": False, "error": "forbidden",
                             "role": role})
            return None
        return role

    # -- routes ---------------------------------------------------------------

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path in ("/", "/index.html"):
            return self._static("index.html", "text/html; charset=utf-8")
        if path == "/style.css":
            return self._static("style.css", "text/css")
        if path == "/app.js":
            return self._static("app.js", "application/javascript")
        if path == "/api/status":
            if self._require(("admin", "viewer")) is None:
                return
            return self._send(200, APP.status.build_status())
        if path == "/api/alerts":
            if self._require(("admin", "viewer")) is None:
                return
            return self._send(200, {
                "active": APP.alerts.active_alerts(),
                "recent": APP.logs.query(source="alerts", limit=50),
            })
        if path == "/api/logs":
            if self._require(("admin",)) is None:
                return
            params = parse_qs(parsed.query)
            entries = APP.logs.query(
                source=_first(params, "source"),
                module=_first(params, "module"),
                severity=_first(params, "severity"),
                q=_first(params, "q"),
                limit=int(_first(params, "limit", "200")))
            return self._send(200, {"entries": entries})
        if path == "/api/logs/export":
            if self._require(("admin",)) is None:
                return
            params = parse_qs(parsed.query)
            text = APP.logs.export_text(
                source=_first(params, "source"),
                module=_first(params, "module"),
                severity=_first(params, "severity"),
                q=_first(params, "q"))
            return self._send(200, text, "text/plain; charset=utf-8",
                              {"Content-Disposition":
                               "attachment; filename=iwt-diagnostics.txt"})
        return self._send(404, {"ok": False, "error": "not_found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/api/login":
            return self._login()
        if path == "/api/logout":
            jar = cookies.SimpleCookie(self.headers.get("Cookie", ""))
            morsel = jar.get("iwt_session")
            if morsel:
                APP.drop_session(morsel.value)
            return self._send(200, {"ok": True}, extra_headers={
                "Set-Cookie": "iwt_session=; Path=/; Max-Age=0"})
        if path == "/api/control":
            role = self._require(("admin",))
            if role is None:
                return
            return self._control(role)
        return self._send(404, {"ok": False, "error": "not_found"})

    # -- handlers ---------------------------------------------------------------

    def _static(self, name, content_type):
        path = os.path.join(HERE, "static", name)
        try:
            with open(path, "rb") as handle:
                payload = handle.read()
        except OSError:
            return self._send(404, {"ok": False, "error": "not_found"})
        return self._send(200, payload, content_type)

    def _login(self):
        ip = self.client_address[0]
        if APP.login_locked(ip):
            return self._send(429, {"ok": False,
                                    "error": "login_rate_limited"})
        body = self._json_body()
        role = APP.role_for_token(str(body.get("token", "")))
        if role is None:
            APP.note_login_failure(ip)
            APP.log("warn", "login failed from %s" % ip)
            return self._send(401, {"ok": False,
                                    "error": "invalid_token"})
        session_id = APP.create_session(role)
        APP.log("info", "login ok role=%s from %s" % (role, ip))
        return self._send(200, {"ok": True, "role": role}, extra_headers={
            "Set-Cookie": "iwt_session=%s; Path=/; HttpOnly; "
                          "SameSite=Strict" % session_id})

    def _control(self, role):
        body = self._json_body()
        action = str(body.get("action", ""))
        control = APP.control
        if action == "health_check":
            result = APP.status.run_health_check()
        elif action == "game_start":
            result = control.start_game()
        elif action == "game_stop":
            result = control.stop_game()
        elif action == "game_restart":
            result = control.restart_game()
        elif action == "game_command":
            result = control.send_game_cmd(
                str(body.get("command", "")),
                body.get("params") or {})
        elif action == "stream_service_start":
            result = control.start_stream_service()
        elif action == "stream_service_stop":
            result = control.stop_stream_service()
        elif action == "stream_service_restart":
            result = control.restart_stream_service()
        elif action == "stream_command":
            result = self._stream_command(body)
        else:
            result = {"ok": False, "error": "unknown_action"}
        APP.audit(role, action, result if isinstance(result, dict)
                  else {"ok": False})
        APP.log("info" if result.get("ok") else "warn",
                "control %s -> %s" % (action,
                                      "ok" if result.get("ok") else
                                      result.get("error", "error")))
        return self._send(200, result)

    def _stream_command(self, body):
        # Stream commands run through the persistent stream service
        # into the real Phase 07 StreamAdmin. If the service is not
        # running yet, start it first — that is process control's
        # job, and the combined result says so honestly.
        command = str(body.get("command", ""))
        extra = {}
        if command in ("start", "restart"):
            extra["confirm_public"] = bool(body.get("confirm_public",
                                                    False))
        if command == "configure_quality":
            extra["preset"] = str(body.get("preset", ""))
        if command == "set_auto_recovery":
            extra["enabled"] = bool(body.get("enabled", True))
        state = APP.control.stream_state()
        boot = None
        if not state["running"]:
            boot = APP.control.start_stream_service()
            if not boot.get("ok"):
                return {"ok": False, "error": "stream_service_start_failed",
                        "boot": boot}
            deadline = time.time() + 8.0
            while time.time() < deadline:
                if os.path.exists(CFG.stream_status_path):
                    break
                time.sleep(0.1)
        result = APP.control.send_stream_cmd(command, extra)
        if boot is not None:
            result = dict(result)
            result["service_boot"] = boot
        return result


def _first(params, name, default=None):
    values = params.get(name)
    return values[0] if values else default


def main():
    if not CFG.admin_token:
        print("WARNING: IWT_ADMIN_TOKEN is not set — login is impossible "
              "until it is. Set it (and optionally IWT_VIEWER_TOKEN) "
              "in the environment; never in the repo.", file=sys.stderr)
    APP.alerts.start()
    APP.log("info", "dashboard started on %s:%d" % (CFG.host, CFG.port))
    server = ThreadingHTTPServer((CFG.host, CFG.port), Handler)
    print("INFINITE WORLD TV dashboard: http://%s:%d" % (CFG.host,
                                                         CFG.port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        APP.alerts.stop()
        server.server_close()


if __name__ == "__main__":
    main()
