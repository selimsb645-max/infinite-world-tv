#!/usr/bin/env python3
"""Phase 08 dashboard test suite.

Starts two real dashboard server instances (stdlib http.server)
against temporary runtime dirs and drives them over HTTP:

  Instance A — NO stream key in the environment: streaming must
    report NOT CONFIGURED, the game STOPPED. Covers page serving,
    responsive markers, auth, roles, rate limiting, health check,
    audit, log filtering.
  Instance B — fake stream key + local dead RTMP ingest
    (rtmp://127.0.0.1:19359 — nothing ever leaves this machine):
    covers the real control round-trips — game start/AI/pause/
    resume/stop through the Phase 08 bridge, stream prepare /
    public-confirmation safeguard / start / stop / quality /
    auto-recovery through the real Phase 07 StreamAdmin — plus
    secret redaction of a planted log line.

Prints PASS/FAIL per check and DASHBOARD_DONE failures=N.
"""
import http.cookiejar
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("IWT_GODOT_BIN") or shutil.which("godot") or ""
ADMIN = "test-admin-token-08"
VIEWER = "test-viewer-token-08"
FAKE_KEY = "FAKEKEY-test-1234567890"

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print("PASS: %s" % name)
    else:
        print("FAIL: %s %s" % (name, detail))
        FAILURES.append(name)


class Client:
    def __init__(self, port):
        self.base = "http://127.0.0.1:%d" % port
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar))

    def request(self, method, path, body=None, raw=False):
        data = None
        headers = {}
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data,
                                     headers=headers, method=method)
        try:
            with self.opener.open(req, timeout=30) as resp:
                payload = resp.read()
                if raw:
                    return resp.status, payload.decode("utf-8", "replace"), resp.headers
                return resp.status, json.loads(payload or b"{}"), resp.headers
        except urllib.error.HTTPError as exc:
            payload = exc.read()
            if raw:
                return exc.code, payload.decode("utf-8", "replace"), exc.headers
            try:
                return exc.code, json.loads(payload or b"{}"), exc.headers
            except ValueError:
                return exc.code, {}, exc.headers

    def get(self, path, raw=False):
        return self.request("GET", path, raw=raw)

    def post(self, path, body=None):
        return self.request("POST", path, body or {})


def start_server(port, runtime, extra_env):
    env = dict(os.environ)
    env.update({
        "IWT_DASHBOARD_HOST": "127.0.0.1",
        "IWT_DASHBOARD_PORT": str(port),
        "IWT_ADMIN_TOKEN": ADMIN,
        "IWT_VIEWER_TOKEN": VIEWER,
        "IWT_DASHBOARD_RUNTIME": runtime,
        "IWT_GODOT_BIN": GODOT,
        "IWT_GAME_DISPLAY_MODE": "headless",
    })
    env.pop("IWT_YOUTUBE_STREAM_KEY", None)
    env.update(extra_env)
    proc = subprocess.Popen(
        [sys.executable, os.path.join(ROOT, "dashboard", "server.py")],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        start_new_session=True)
    client = Client(port)
    deadline = time.time() + 20
    while time.time() < deadline:
        try:
            status, _, _ = client.get("/", raw=True)
            if status == 200:
                return proc, client
        except Exception:
            pass
        time.sleep(0.2)
    raise RuntimeError("dashboard on port %d did not start" % port)


def stop_server(proc):
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        proc.wait(timeout=8)
    except Exception:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except Exception:
            pass


def wait_for(client, predicate, timeout=45.0, interval=0.5):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        status, data, _ = client.get("/api/status")
        if status == 200:
            last = data
            if predicate(data):
                return data
        time.sleep(interval)
    return last


def control(client, payload):
    status, data, _ = client.post("/api/control", payload)
    assert status == 200, "control HTTP %d" % status
    return data


def instance_a(tmp):
    print("--- instance A: no stream key ---")
    runtime = os.path.join(tmp, "runtime_a")
    proc, client = start_server(18791, runtime, {})
    try:
        status, page, _ = client.get("/", raw=True)
        check("page_served", status == 200 and "Admin Dashboard" in page)
        check("page_has_viewport_meta", 'name="viewport"' in page)
        status, css, _ = client.get("/style.css", raw=True)
        check("css_has_responsive_media_query",
              status == 200 and "@media" in css)
        status, _, _ = client.get("/api/status")
        check("status_requires_auth_401", status == 401)
        status, _, _ = client.post("/api/login", {"token": "wrong"})
        check("login_wrong_token_401", status == 401)

        status, data, _ = client.post("/api/login", {"token": ADMIN})
        check("admin_login_ok", status == 200 and data.get("role") == "admin")
        status, data, _ = client.get("/api/status")
        check("status_stream_not_configured",
              data["streaming"]["label"] == "NOT CONFIGURED",
              str(data["streaming"]))
        check("status_game_stopped", data["game"]["label"] == "STOPPED")
        check("status_overall_offline", data["overall"] == "OFFLINE")
        check("status_system_real",
              data["system"]["ram"]["total_mb"] > 0
              and data["system"]["disk"]["total_gb"] > 0)

        result = control(client, {"action": "health_check"})
        check("health_check_roundtrip", result.get("ok") is True,
              str(result))
        status, data, _ = client.get("/api/status")
        check("health_check_recorded",
              (data["monitoring"].get("last_health_check") or {}).get(
                  "overall") is not None)

        audit_path = os.path.join(runtime, "audit.jsonl")
        audit_text = ""
        if os.path.exists(audit_path):
            with open(audit_path) as handle:
                audit_text = handle.read()
        check("audit_log_records_actions", "health_check" in audit_text)
        check("audit_log_has_no_tokens",
              ADMIN not in audit_text and VIEWER not in audit_text)

        status, data, _ = client.get(
            "/api/logs?source=dashboard&severity=warn")
        entries = data.get("entries", [])
        check("log_filter_severity",
              status == 200 and len(entries) >= 1
              and all(e["severity"] == "warn" for e in entries),
              str(entries[:2]))

        viewer = Client(18791)
        status, data, _ = viewer.post("/api/login", {"token": VIEWER})
        check("viewer_login_ok", status == 200
              and data.get("role") == "viewer")
        status, _, _ = viewer.get("/api/status")
        check("viewer_can_read_status", status == 200)
        status, _, _ = viewer.post("/api/control",
                                   {"action": "health_check"})
        check("viewer_control_forbidden_403", status == 403)
        status, _, _ = viewer.get("/api/logs")
        check("viewer_logs_forbidden_403", status == 403)

        # Rate limiting last: it locks /api/login for this IP.
        got_429 = False
        for _ in range(8):
            status, _, _ = client.post("/api/login", {"token": "wrong"})
            if status == 429:
                got_429 = True
                break
        check("login_rate_limited_429", got_429)
    finally:
        stop_server(proc)


def instance_b(tmp):
    print("--- instance B: fake key, local ingest, real controls ---")
    runtime = os.path.join(tmp, "runtime_b")
    video_file = os.path.join(tmp, "test_input.mp4")
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi",
         "-i", "testsrc=duration=2:size=320x240:rate=24", "-c:v", "libx264",
         "-pix_fmt", "yuv420p", "-y", video_file], check=True)
    proc, client = start_server(18792, runtime, {
        "IWT_YOUTUBE_STREAM_KEY": FAKE_KEY,
        "IWT_RTMP_INGEST_URL": "rtmp://127.0.0.1:19359/live",
        "IWT_STREAM_VISIBILITY": "public",
        "IWT_STREAM_VIDEO_FILE": video_file,
    })
    try:
        status, data, _ = client.post("/api/login", {"token": ADMIN})
        check("b_admin_login_ok", status == 200)

        result = control(client, {"action": "game_start"})
        check("game_start_ok", result.get("ok") is True, str(result))
        data = wait_for(client, lambda s: s["game"]["running"]
                        and s["game"].get("state"))
        check("game_status_running_real",
              bool(data) and data["game"]["label"] == "RUNNING"
              and data["game"]["state"] in ("MENU", "PLAYING", "PAUSED"),
              str((data or {}).get("game")))

        result = control(client, {"action": "game_start"})
        check("game_duplicate_start_refused",
              result.get("ok") is False
              and result.get("error") == "already_running", str(result))

        result = control(client, {"action": "game_command",
                                  "command": "start_ai",
                                  "params": {"seed": 4242}})
        check("game_start_ai_ok", result.get("ok") is True, str(result))
        data = wait_for(client, lambda s: s["ai"]["label"] == "RUNNING"
                        and s["game"].get("state") == "PLAYING")
        check("ai_running_status_real",
              bool(data) and data["ai"]["enabled"] is True
              and bool(data["game"].get("world")),
              str((data or {}).get("ai")))

        result = control(client, {"action": "game_command",
                                  "command": "pause_ai"})
        check("game_pause_ai_ok", result.get("ok") is True, str(result))
        data = wait_for(client, lambda s: s["ai"]["label"] == "STOPPED",
                        timeout=15)
        check("ai_paused_status_real",
              bool(data) and data["ai"]["enabled"] is False)
        result = control(client, {"action": "game_command",
                                  "command": "resume_ai"})
        check("game_resume_ai_ok", result.get("ok") is True, str(result))
        data = wait_for(client, lambda s: s["ai"]["label"] == "RUNNING",
                        timeout=15)
        check("ai_resumed_status_real", bool(data))

        result = control(client, {"action": "stream_command",
                                  "command": "prepare"})
        check("stream_prepare_ok", result.get("ok") is True, str(result))
        result = control(client, {"action": "stream_command",
                                  "command": "start"})
        check("stream_public_start_refused_without_confirm",
              result.get("ok") is False
              and result.get("error") == "public_confirmation_required",
              str(result))
        result = control(client, {"action": "stream_command",
                                  "command": "start",
                                  "confirm_public": True})
        check("stream_start_with_confirm_ok",
              result.get("ok") is True, str(result))
        result = control(client, {"action": "stream_command",
                                  "command": "health"})
        check("stream_health_command_ok",
              result.get("ok") is True
              and "state" in (result.get("status") or {}), str(result))
        result = control(client, {"action": "stream_command",
                                  "command": "stop"})
        check("stream_stop_ok", result.get("ok") is True, str(result))
        result = control(client, {"action": "stream_command",
                                  "command": "configure_quality",
                                  "preset": "720p"})
        check("stream_quality_config_ok", result.get("ok") is True,
              str(result))
        result = control(client, {"action": "stream_command",
                                  "command": "set_auto_recovery",
                                  "enabled": False})
        check("stream_auto_recovery_toggle_ok",
              result.get("ok") is True
              and result.get("auto_recovery") is False, str(result))

        # Redaction: plant the fake key in the stream log, then read
        # it back through the API — it must never survive.
        stream_log = os.path.join(runtime, "stream", "stream_log.jsonl")
        with open(stream_log, "a") as handle:
            handle.write(json.dumps({
                "ts": "2026-11-25T00:00:00", "level": "info",
                "event": "planted",
                "detail": "key %s via rtmps://a.rtmps.youtube.com/live2/%s"
                          % (FAKE_KEY, FAKE_KEY)}) + "\n")
        status, data, _ = client.get("/api/logs?source=stream&q=planted")
        text = json.dumps(data)
        entries = data.get("entries", [])
        check("log_search_keyword",
              status == 200 and len(entries) >= 1
              and all("planted" in e["message"] for e in entries),
              str(entries[:1]))
        check("redaction_in_logs", FAKE_KEY not in text and "***" in text)
        status, raw_status, _ = client.get("/api/status", raw=True)
        check("redaction_in_status", FAKE_KEY not in raw_status)
        status, export, headers = client.get(
            "/api/logs/export?source=stream", raw=True)
        check("log_export_ok",
              status == 200 and FAKE_KEY not in export
              and "attachment" in (headers.get("Content-Disposition") or ""),
              str(status))

        result = control(client, {"action": "game_stop"})
        check("game_stop_ok", result.get("ok") is True, str(result))
        data = wait_for(client, lambda s: s["game"]["label"] == "STOPPED",
                        timeout=20)
        check("game_stopped_status_real", bool(data))
        result = control(client, {"action": "stream_service_stop"})
        check("stream_service_stop_ok", result.get("ok") is True,
              str(result))
        status, data, _ = client.get("/api/status")
        check("status_ok_with_modules_offline",
              status == 200 and data["game"]["label"] == "STOPPED"
              and data["streaming"]["label"] == "OFFLINE",
              str(data.get("streaming")))
    finally:
        stop_server(proc)


def main():
    if not GODOT:
        print("FAIL: godot binary not found (set IWT_GODOT_BIN or GODOT)")
        print("DASHBOARD_DONE failures=1")
        return 1
    tmp = tempfile.mkdtemp(prefix="iwt_dashboard_test_")
    try:
        instance_a(tmp)
        instance_b(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("DASHBOARD_DONE failures=%d" % len(FAILURES))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
