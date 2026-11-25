#!/usr/bin/env python3
"""Phase 10 — END-TO-END integration, leg 2 (system topology).

Runs the REAL production topology in a throwaway runtime dir:
the Phase 09 supervisor owns the game service, the stream
service and the Phase 08 dashboard backend. Over HTTP and the
bridge status files this driver asserts:

  * the supervisor starts and tracks all three units;
  * the dashboard requires auth and its /api/status aggregates
    REAL sections (system metrics present; streaming honestly
    NOT CONFIGURED — this leg exports no stream key);
  * a dashboard control command (start_ai) drives the real
    chain dashboard -> bridge -> GameManager -> generated level
    -> AutonomousController, visible in game_status.json AND
    reflected in /api/status;
  * an injected fault (SIGKILL to the game process) is detected
    and recovered by the supervisor with a new pid, while the
    dashboard stays up throughout.

No stream key is configured and no stream is started; nothing
leaves this machine. Prints PASS/FAIL per check and
INTEGRATION_SYSTEM_DONE failures=N.
"""
import http.cookiejar
import json
import os
import shutil
import signal
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "dashboard"))

import supervisor as sup  # noqa: E402

GODOT = (os.environ.get("IWT_GODOT_BIN") or os.environ.get("GODOT")
         or "godot")
PORT = int(os.environ.get("IWT_INTEGRATION_PORT", "8917"))
RUNTIME = os.environ.get("IWT_INTEGRATION_RUNTIME", "/tmp/iwt_integration")
ADMIN = "integration-admin-token"
VIEWER = "integration-viewer-token"

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print("PASS: %s" % name)
    else:
        print("FAIL: %s %s" % (name, detail))
        FAILURES.append(name)


def read_json(path):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def poll_until(fn, timeout, interval=0.5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = fn()
        if value:
            return value
        time.sleep(interval)
    return None


class Client:
    def __init__(self, port):
        self.base = "http://127.0.0.1:%d" % port
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar))

    def request(self, method, path, body=None):
        data = None
        headers = {}
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data,
                                     headers=headers, method=method)
        try:
            with self.opener.open(req, timeout=30) as resp:
                return resp.status, json.loads(resp.read() or b"{}")
        except urllib.error.HTTPError as exc:
            try:
                return exc.code, json.loads(exc.read() or b"{}")
            except ValueError:
                return exc.code, {}
        except Exception:
            return None, {}

    def get(self, path):
        return self.request("GET", path)

    def post(self, path, body=None):
        return self.request("POST", path, body or {})


def main():
    # This leg deliberately runs with NO stream key anywhere:
    # streaming must report NOT CONFIGURED, and nothing can start.
    os.environ.pop("IWT_YOUTUBE_STREAM_KEY", None)
    if os.path.isdir(RUNTIME):
        shutil.rmtree(RUNTIME)
    os.makedirs(RUNTIME)

    units = sup.default_units(GODOT, RUNTIME)
    for unit in units:
        if unit.name == "dashboard":
            unit.env.update({
                "IWT_DASHBOARD_PORT": str(PORT),
                "IWT_ADMIN_TOKEN": ADMIN,
                "IWT_VIEWER_TOKEN": VIEWER,
                "IWT_GAME_DISPLAY_MODE": "headless",
            })
            unit.env.pop("IWT_YOUTUBE_STREAM_KEY", None)
    sv = sup.Supervisor(RUNTIME, units)
    if not sv.acquire_lock():
        print("INTEGRATION_SYSTEM_DONE failures=1 (supervisor lock refused)")
        return 1

    stop_tick = threading.Event()

    def tick_loop():
        while not stop_tick.is_set():
            try:
                sv.tick()
            except Exception:
                pass
            time.sleep(0.5)

    status_path = os.path.join(RUNTIME, "supervisor_status.json")
    game_status_path = os.path.join(RUNTIME, "game", "game_status.json")
    try:
        results = sv.start_all()
        check("supervisor_starts_all_units",
              all(v.get("ok") for v in results.values()),
              str(results))
        ticker = threading.Thread(target=tick_loop, daemon=True)
        ticker.start()

        def all_running():
            snap = read_json(status_path)
            if not snap:
                return None
            states = {n: u.get("state")
                      for n, u in snap.get("units", {}).items()}
            return states if states and all(
                s == "RUNNING" for s in states.values()) else None

        states = poll_until(all_running, 60)
        check("supervisor_tracks_units_running", states is not None
              and set(states) == {"game", "stream", "dashboard"},
              str(states))

        client = Client(PORT)

        def dashboard_reachable():
            try:
                req = urllib.request.Request(
                    client.base + "/", method="GET")
                with urllib.request.urlopen(req, timeout=3) as resp:
                    return resp.status == 200
            except Exception:
                return False

        # The supervisor reports the dashboard unit RUNNING as soon
        # as the process exists; the HTTP listener can lag behind
        # it on this loaded VM, so wait for real reachability.
        check("dashboard_http_reachable",
              poll_until(dashboard_reachable, 60) is not None)
        status_code, _ = client.get("/api/status")
        check("dashboard_status_requires_auth", status_code in (401, 403),
              "got %s" % status_code)
        status_code, data = client.post("/api/login", {"token": ADMIN})
        check("dashboard_admin_login",
              status_code == 200 and data.get("role") == "admin",
              "got %s %s" % (status_code, data))
        status_code, status = client.get("/api/status")
        check("dashboard_status_ok", status_code == 200
              and "game" in status and "streaming" in status
              and "system" in status, "got %s" % status_code)
        system = status.get("system", {})
        check("dashboard_system_metrics_real",
              isinstance(system.get("cpu_percent"), (int, float))
              and "ram" in system and "disk" in system,
              str(system)[:200])
        check("dashboard_stream_not_configured",
              status.get("streaming", {}).get("label") == "NOT CONFIGURED",
              str(status.get("streaming", {}))[:200])

        # Dashboard control -> bridge -> GameManager -> autopilot.
        status_code, result = client.post("/api/control", {
            "action": "game_command", "command": "start_ai",
            "params": {"seed": 20250}})
        check("dashboard_start_ai_command",
              status_code == 200 and result.get("ok") is True,
              "got %s %s" % (status_code, result))

        def game_playing():
            snap = read_json(game_status_path)
            if not snap:
                return None
            ai = snap.get("ai") or {}
            if snap.get("state") == "PLAYING" and ai.get("enabled") \
                    and snap.get("level_seed") is not None \
                    and snap.get("endless_active"):
                return snap
            return None

        snap = poll_until(game_playing, 90)
        check("bridge_reports_generated_level_and_ai", snap is not None,
              str(read_json(game_status_path))[:200])
        if snap:
            print("MEASURED bridge: state=%s mode=%s seed=%s world=%s "
                  "fps=%s" % (snap.get("state"), snap.get("mode"),
                              snap.get("level_seed"), snap.get("world"),
                              snap.get("fps")))
        status_code, status = client.get("/api/status")
        game_section = status.get("game", {})
        check("dashboard_reflects_playing_game",
              status_code == 200
              and game_section.get("state") == "PLAYING"
              and game_section.get("level_seed") is not None,
              str(game_section)[:200])
        ai_section = status.get("ai", {})
        check("dashboard_reflects_ai_running",
              ai_section.get("label") == "RUNNING"
              and ai_section.get("enabled") is True,
              str(ai_section)[:200])

        # Fault injection: SIGKILL the game; supervisor must recover
        # it with a new pid while the dashboard stays up.
        sup_snap = read_json(status_path)
        old_pid = sup_snap["units"]["game"]["pid"]
        os.kill(old_pid, signal.SIGKILL)
        print("MEASURED injected SIGKILL unit=game pid=%s" % old_pid)

        def game_recovered():
            snap2 = read_json(status_path)
            if not snap2:
                return None
            unit = snap2.get("units", {}).get("game", {})
            if unit.get("state") == "RUNNING" and unit.get("pid") \
                    and unit.get("pid") != old_pid \
                    and sup.pid_alive(unit["pid"]):
                return unit
            return None

        unit = poll_until(game_recovered, 90)
        check("supervisor_recovers_killed_game", unit is not None,
              str(read_json(status_path))[:300])
        if unit:
            print("MEASURED recovered unit=game new_pid=%s restarts=%s"
                  % (unit.get("pid"), unit.get("total_restarts")))
        status_code, _ = client.get("/api/status")
        check("dashboard_survives_game_fault", status_code == 200,
              "got %s" % status_code)

        def bridge_new_pid():
            snap3 = read_json(game_status_path)
            if snap3 and snap3.get("service_pid") not in (None, old_pid):
                return snap3
            return None

        snap3 = poll_until(bridge_new_pid, 30)
        check("bridge_resumes_after_recovery", snap3 is not None,
              str(read_json(game_status_path))[:200])
    finally:
        stop_tick.set()
        sv.stop_all()
        sv.release_lock()

    print("INTEGRATION_SYSTEM_DONE failures=%d" % len(FAILURES))
    return 0 if not FAILURES else 1


if __name__ == "__main__":
    sys.exit(main())
