#!/usr/bin/env python3
"""INFINITE WORLD TV — streaming session driver.

Runs ONE bounded streaming session on top of the project's real
production topology, exactly as the Phase 08 dashboard and the
Phase 09 supervisor define it:

  * dashboard/supervisor.py owns the three units (game, stream,
    dashboard) — this driver does NOT reimplement supervision;
    it instantiates the same Supervisor class the stability and
    integration harnesses use, with the same default units.
  * The game unit's argv follows the dashboard's own headful
    recipe (dashboard/process_control.py `_game_argv`, "windowed"
    when a display exists): Phase 06 capture needs real pixels,
    so the game runs under the Xvfb display this driver starts,
    not under the supervisor's --headless default.
  * All driving goes through the real dashboard HTTP API
    (login -> /api/control game_command / stream_command), the
    same path tests/integration_test.py exercises.

Modes (IWT_SESSION_MODE / --mode):

  prepare_only  SAFE DEFAULT. The stream key is REMOVED from the
                environment before any unit starts, so streaming
                cannot be configured, let alone started. The full
                stack comes up, the AI plays, the Phase 06
                renderer runs, and the dashboard must honestly
                report streaming NOT CONFIGURED.
  private_test  Requires IWT_YOUTUBE_STREAM_KEY in the
                environment. Visibility is forced to "private".
                Stage A renders a real game segment; stage B
                restarts the stack with that segment as the
                stream service's video source and starts the
                (private) stream through StreamAdmin.
  live          Like private_test, but visibility "public" and
                the start carries confirm_public=true. Refused
                BEFORE anything starts unless the environment
                variable IWT_CONFIRM_PUBLIC is exactly
                "I_CONFIRM_PUBLIC_STREAM" — the project's own
                public-confirmation gate is passed through, never
                bypassed.

Secrets are read from the environment only, are never printed,
never written to any file this driver creates, and are passed to
units solely through process-environment inheritance (the same
channel the supervisor itself uses).

Outputs land in the session dir (IWT_SESSION_DIR or
session_output/<timestamp>): session_log.txt,
status_snapshots.jsonl, session_status.json,
session_summary.json, recordings_index.json and copies of the
unit logs under logs/. The Phase 07/08/09 code redacts the stream
key from every log and status field it produces; this driver
adds no unredacted copy of anything.

Usage:
  python3 scripts/stream_session.py [--mode MODE]
      [--duration-sec N] [--port N] [--session-dir DIR]
"""
import argparse
import http.cookiejar
import json
import os
import secrets
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "dashboard"))

import supervisor as sup  # noqa: E402  (the project's own module)

CONFIRM_PHRASE = "I_CONFIRM_PUBLIC_STREAM"
MODES = ("prepare_only", "private_test", "live")
MAX_DURATION_SEC = 350 * 60

# Bounded waits (seconds). Generous: a loaded shared runner is
# slow, and every wait is a health gate, not a sleep-and-hope.
WAIT_DASHBOARD_HTTP = 180.0
WAIT_UNITS_RUNNING = 180.0
WAIT_GAME_PLAYING = 300.0
WAIT_SOURCE_SEGMENT = 1200.0
WAIT_STREAMING = 180.0
SNAPSHOT_INTERVAL = 15.0


def read_json(path):
    try:
        with open(path, "r") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def poll_until(fn, timeout, interval=1.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = fn()
        if value:
            return value
        time.sleep(interval)
    return None


class Client:
    """Minimal dashboard client (cookie session), stdlib only."""

    def __init__(self, port):
        self.base = "http://127.0.0.1:%d" % port
        jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(jar))

    def request(self, method, path, body=None):
        data = None
        headers = {}
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data,
                                     headers=headers, method=method)
        try:
            with self.opener.open(req, timeout=10) as resp:
                return resp.status, json.loads(resp.read().decode())
        except urllib.error.HTTPError as exc:
            try:
                return exc.code, json.loads(exc.read().decode())
            except Exception:
                return exc.code, {}
        except Exception:
            return None, {}

    def get(self, path):
        return self.request("GET", path)

    def post(self, path, body=None):
        return self.request("POST", path, body or {})


class Session:
    def __init__(self, args):
        self.mode = args.mode
        self.duration_sec = args.duration_sec
        self.port = args.port
        self.session_dir = args.session_dir
        self.recordings_dir = os.path.join(self.session_dir, "recordings")
        self.log_path = os.path.join(self.session_dir, "session_log.txt")
        self.snapshots_path = os.path.join(
            self.session_dir, "status_snapshots.jsonl")
        self.failures = []
        self.gates = {}
        self.stop_requested = threading.Event()
        self.xvfb_proc = None
        self.supervisor = None
        self.tick_thread = None
        self.tick_stop = threading.Event()
        self.runtime_dir = None
        self.started_at = None
        self.deadline = None
        os.makedirs(self.recordings_dir, exist_ok=True)

    # -- logging (never secrets: this driver never logs env values)

    def log(self, message):
        line = "%s %s" % (time.strftime("%Y-%m-%dT%H:%M:%SZ",
                                        time.gmtime()), message)
        print(line, flush=True)
        try:
            with open(self.log_path, "a") as handle:
                handle.write(line + "\n")
        except OSError:
            pass

    def gate(self, name, ok, detail=""):
        self.gates[name] = bool(ok)
        self.log("GATE %s=%s %s" % (name, "ok" if ok else "FAIL", detail))
        if not ok:
            self.failures.append(name)
        return ok

    # -- environment contract -------------------------------------

    def prepare_environment(self):
        """Enforce the per-mode secret contract BEFORE anything
        starts. Returns None on success, or a refusal message."""
        if not os.environ.get("IWT_ADMIN_TOKEN"):
            # Ephemeral per-session token: kept in this process's
            # memory / unit environments only, never written down.
            os.environ["IWT_ADMIN_TOKEN"] = secrets.token_hex(16)
            self.log("IWT_ADMIN_TOKEN not set; generated an "
                     "ephemeral per-session token (not recorded)")
        if self.mode == "prepare_only":
            removed = os.environ.pop("IWT_YOUTUBE_STREAM_KEY", None)
            os.environ["IWT_STREAM_VISIBILITY"] = "private"
            self.log("mode=prepare_only: stream key %s; visibility "
                     "forced to private; streaming cannot start"
                     % ("removed from environment" if removed
                        else "absent"))
            return None
        if not os.environ.get("IWT_YOUTUBE_STREAM_KEY"):
            return ("mode=%s refused: IWT_YOUTUBE_STREAM_KEY is not "
                    "set in the environment" % self.mode)
        if self.mode == "private_test":
            os.environ["IWT_STREAM_VISIBILITY"] = "private"
            self.log("mode=private_test: stream key present; "
                     "visibility forced to private")
            return None
        # live
        if os.environ.get("IWT_CONFIRM_PUBLIC") != CONFIRM_PHRASE:
            return ("mode=live refused: IWT_CONFIRM_PUBLIC must be "
                    "exactly %r to pass the project's public-"
                    "confirmation gate" % CONFIRM_PHRASE)
        os.environ["IWT_STREAM_VISIBILITY"] = "public"
        self.log("mode=live: stream key present; public "
                 "confirmation phrase accepted; the start command "
                 "will carry confirm_public=true through "
                 "StreamAdmin (the project's own gate)")
        return None

    # -- Xvfb -------------------------------------------------------

    def start_xvfb(self):
        if os.environ.get("DISPLAY"):
            self.log("DISPLAY already set (%s); using it"
                     % os.environ["DISPLAY"])
            return True
        for num in (99, 100, 101, 102):
            socket_path = "/tmp/.X11-unix/X%d" % num
            if os.path.exists(socket_path):
                continue
            proc = subprocess.Popen(
                ["Xvfb", ":%d" % num, "-screen", "0", "1280x720x24",
                 "-nolisten", "tcp"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            ok = poll_until(lambda: os.path.exists(socket_path),
                            10.0, 0.2)
            if ok and proc.poll() is None:
                os.environ["DISPLAY"] = ":%d" % num
                self.xvfb_proc = proc
                self.log("Xvfb started on :%d (1280x720x24)" % num)
                return True
            proc.terminate()
        self.log("could not start Xvfb on any display number")
        return False

    # -- stack lifecycle ---------------------------------------------

    def build_units(self, godot, runtime_dir, stream_video_file=""):
        units = sup.default_units(godot, runtime_dir)
        for unit in units:
            if unit.name == "game":
                # Headful recipe from dashboard/process_control.py
                # (_game_argv "windowed"): real pixels for the
                # Phase 06 capture chain, under our Xvfb display.
                unit.argv = [godot, "--path",
                             os.path.join(ROOT, "game"),
                             "res://dashboard/GameService.tscn"]
            elif unit.name == "dashboard":
                unit.env.update({"IWT_DASHBOARD_PORT": str(self.port)})
            elif unit.name == "stream" and stream_video_file:
                unit.env.update(
                    {"IWT_STREAM_VIDEO_FILE": stream_video_file})
        return units

    def start_stack(self, godot, stage, stream_video_file=""):
        runtime_dir = os.path.join(self.session_dir, "runtime_" + stage)
        os.makedirs(runtime_dir, exist_ok=True)
        self.runtime_dir = runtime_dir
        units = self.build_units(godot, runtime_dir, stream_video_file)
        sv = sup.Supervisor(runtime_dir, units)
        if not sv.acquire_lock():
            self.log("supervisor lock refused for %s" % runtime_dir)
            return False
        self.supervisor = sv
        self.tick_stop.clear()

        def tick_loop():
            while not self.tick_stop.is_set():
                try:
                    sv.tick()
                except Exception:
                    pass
                time.sleep(0.5)

        self.tick_thread = threading.Thread(target=tick_loop,
                                            daemon=True)
        results = sv.start_all()
        ok = all(v.get("ok") for v in results.values())
        self.log("stage %s: supervisor start_all -> %s"
                 % (stage, {k: v.get("ok") for k, v in results.items()}))
        if not ok:
            return False
        self.tick_thread.start()

        status_path = os.path.join(runtime_dir, "supervisor_status.json")

        def all_running():
            snap = read_json(status_path)
            if not snap:
                return None
            states = {n: u.get("state")
                      for n, u in snap.get("units", {}).items()}
            if states and all(s == "RUNNING" for s in states.values()):
                return states
            return None

        states = poll_until(all_running, WAIT_UNITS_RUNNING)
        self.log("stage %s: unit states -> %s" % (stage, states))
        return states is not None

    def stop_stack(self):
        if self.supervisor is None:
            return
        self.tick_stop.set()
        if self.tick_thread is not None:
            self.tick_thread.join(timeout=5)
            self.tick_thread = None
        try:
            self.supervisor.stop_all()
        except Exception as exc:
            self.log("supervisor stop_all raised %r" % (exc,))
        try:
            self.supervisor.release_lock()
        except Exception:
            pass
        self.supervisor = None
        self.log("stack stopped (supervisor graceful shutdown)")

    # -- dashboard driving -------------------------------------------

    def wait_dashboard_and_login(self, client):
        def reachable():
            try:
                req = urllib.request.Request(client.base + "/",
                                             method="GET")
                with urllib.request.urlopen(req, timeout=3) as resp:
                    return resp.status == 200
            except Exception:
                return False

        if not poll_until(reachable, WAIT_DASHBOARD_HTTP):
            return False
        code, data = client.post(
            "/api/login",
            {"token": os.environ.get("IWT_ADMIN_TOKEN", "")})
        return code == 200 and data.get("role") == "admin"

    def control(self, client, body):
        code, data = client.post("/api/control", body)
        return code, data

    def drive_game(self, client):
        """Start autonomous play + the Phase 06 renderer through
        the real dashboard -> bridge -> GameManager path."""
        code, result = self.control(client, {
            "action": "game_command", "command": "start_ai",
            "params": {"seed": 777}})
        if not (code == 200 and result.get("ok") is True):
            self.log("start_ai refused: %s %s" % (code, result))
            return False
        game_status = os.path.join(self.runtime_dir, "game",
                                   "game_status.json")

        def playing():
            snap = read_json(game_status)
            if not snap:
                return None
            ai = snap.get("ai") or {}
            if snap.get("state") == "PLAYING" and ai.get("enabled") \
                    and snap.get("level_seed") is not None:
                return snap
            return None

        snap = poll_until(playing, WAIT_GAME_PLAYING)
        if not snap:
            self.log("game did not reach PLAYING+AI in time")
            return False
        self.log("game PLAYING: world=%s seed=%s fps=%s"
                 % (snap.get("world"), snap.get("level_seed"),
                    snap.get("fps")))
        preset = os.environ.get("IWT_STREAM_PRESET") or "720p"
        code, result = self.control(client, {
            "action": "game_command", "command": "rendering_start",
            "params": {"preset": preset}})
        ok = code == 200 and result.get("ok") is True
        self.log("rendering_start (%s) -> %s %s" % (preset, code, result))
        return ok

    # -- streaming -----------------------------------------------------

    def find_source_segment(self):
        """A finalized Phase 06 segment MP4 (never a .partial)."""
        def candidate():
            try:
                names = sorted(os.listdir(self.recordings_dir))
            except OSError:
                return None
            for name in names:
                if name.endswith(".mp4") and ".partial." not in name:
                    path = os.path.join(self.recordings_dir, name)
                    if os.path.getsize(path) > 0:
                        return path
            return None

        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            return None
        first = poll_until(candidate,
                           min(WAIT_SOURCE_SEGMENT, remaining), 5.0)
        if not first:
            return None
        size1 = os.path.getsize(first)
        time.sleep(5)
        if os.path.exists(first) and os.path.getsize(first) == size1:
            return first
        return first if os.path.exists(first) else None

    def start_streaming(self, client):
        code, result = self.control(client, {
            "action": "stream_command", "command": "prepare"})
        if not self.gate("stream_prepare_ok",
                         code == 200 and result.get("ok") is True,
                         "-> %s %s" % (code, result)):
            return False
        code, result = self.control(client, {
            "action": "stream_command", "command": "start",
            "confirm_public": self.mode == "live"})
        if not self.gate("stream_start_ok",
                         code == 200 and result.get("ok") is True,
                         "-> %s %s" % (code, result)):
            return False
        status_path = os.path.join(self.runtime_dir, "stream",
                                   "stream_status.json")

        def streaming():
            snap = read_json(status_path)
            if snap and snap.get("manager_state") == "streaming":
                return snap
            return None

        snap = poll_until(streaming, WAIT_STREAMING)
        return self.gate("stream_state_streaming", snap is not None)

    def stop_streaming(self, client):
        try:
            code, result = self.control(client, {
                "action": "stream_command", "command": "stop"})
            self.log("stream stop -> %s %s" % (code, result))
        except Exception as exc:
            self.log("stream stop raised %r" % (exc,))

    # -- snapshots ------------------------------------------------------

    def snapshot(self, client):
        snap = {
            "ts": time.time(),
            "mode": self.mode,
            "supervisor": read_json(os.path.join(
                self.runtime_dir, "supervisor_status.json"))
            if self.runtime_dir else None,
            "game": read_json(os.path.join(
                self.runtime_dir, "game", "game_status.json"))
            if self.runtime_dir else None,
            "stream": read_json(os.path.join(
                self.runtime_dir, "stream", "stream_status.json"))
            if self.runtime_dir else None,
        }
        if client is not None:
            code, data = client.get("/api/status")
            snap["dashboard_status_code"] = code
            snap["dashboard"] = data if code == 200 else None
        try:
            with open(self.snapshots_path, "a") as handle:
                handle.write(json.dumps(snap) + "\n")
            tmp = os.path.join(self.session_dir,
                               "session_status.json.tmp")
            with open(tmp, "w") as handle:
                json.dump(snap, handle, indent=1)
            os.replace(tmp, os.path.join(self.session_dir,
                                         "session_status.json"))
        except OSError:
            pass
        game = snap.get("game") or {}
        stream = snap.get("stream") or {}
        self.log("snapshot: game=%s fps=%s stream_state=%s "
                 "stream_key=%s"
                 % (game.get("state"), game.get("fps"),
                    stream.get("manager_state"),
                    stream.get("has_stream_key")))
        return snap

    def hold_until_deadline(self, client):
        while time.monotonic() < self.deadline \
                and not self.stop_requested.is_set():
            self.snapshot(client)
            remaining = self.deadline - time.monotonic()
            self.stop_requested.wait(
                timeout=min(SNAPSHOT_INTERVAL, max(0.0, remaining)))

    # -- main flow -------------------------------------------------------

    def run(self):
        self.started_at = time.time()
        self.deadline = time.monotonic() + self.duration_sec
        refusal = self.prepare_environment()
        if refusal:
            self.log("REFUSED: " + refusal)
            self.write_summary("refused", refusal)
            return 2
        godot = (os.environ.get("IWT_GODOT_BIN")
                 or os.environ.get("GODOT") or shutil.which("godot")
                 or "godot")
        try:
            version = subprocess.run(
                [godot, "--version"], capture_output=True, text=True,
                timeout=30).stdout.strip()
        except Exception as exc:
            self.log("godot binary unusable: %r" % (exc,))
            self.write_summary("failed", "godot_unusable")
            return 1
        self.log("godot: %s (%s)" % (version, godot))
        if "4.3" not in version:
            self.log("WARNING: project targets Godot 4.3; found %r"
                     % version)
        os.environ.setdefault("IWT_RECORDINGS_DIR", self.recordings_dir)
        client = Client(self.port)
        streaming_started = False
        try:
            if not self.gate("xvfb_ready", self.start_xvfb()):
                return 1
            # ---- stage A: full stack, game playing + rendering.
            if not self.gate("stack_up",
                             self.start_stack(godot, "a")):
                return 1
            if not self.gate("dashboard_login",
                             self.wait_dashboard_and_login(client)):
                return 1
            if not self.gate("game_playing", self.drive_game(client)):
                return 1
            code, status = client.get("/api/status")
            streaming_section = (status or {}).get("streaming", {})
            self.log("dashboard streaming section: %s"
                     % (streaming_section,))
            if self.mode == "prepare_only":
                stream_snap = read_json(os.path.join(
                    self.runtime_dir, "stream", "stream_status.json")) \
                    or {}
                self.gate(
                    "stream_not_configured",
                    streaming_section.get("label") == "NOT CONFIGURED"
                    and stream_snap.get("has_stream_key") is False,
                    "label=%s has_stream_key=%s"
                    % (streaming_section.get("label"),
                       stream_snap.get("has_stream_key")))
                self.hold_until_deadline(client)
                return 0 if not self.failures else 1
            # ---- stage B (private_test / live): restart the stack
            # with a real rendered segment as the stream source,
            # then start the stream through StreamAdmin.
            segment = self.find_source_segment()
            if not self.gate("source_segment_ready", segment is not None):
                return 1
            self.log("stream source segment: %s (%d bytes)"
                     % (segment, os.path.getsize(segment)))
            self.stop_stack()
            if self.stop_requested.is_set():
                return 1
            if not self.gate("stack_up_stage_b",
                             self.start_stack(godot, "b",
                                              stream_video_file=segment)):
                return 1
            if not self.gate("dashboard_login_stage_b",
                             self.wait_dashboard_and_login(client)):
                return 1
            if not self.gate("game_playing_stage_b",
                             self.drive_game(client)):
                return 1
            if not self.start_streaming(client):
                return 1
            streaming_started = True
            self.hold_until_deadline(client)
            return 0 if not self.failures else 1
        finally:
            if streaming_started:
                self.stop_streaming(client)
            self.snapshot(None) if self.runtime_dir else None
            self.stop_stack()
            if self.xvfb_proc is not None:
                self.xvfb_proc.terminate()
                try:
                    self.xvfb_proc.wait(timeout=5)
                except Exception:
                    self.xvfb_proc.kill()
                self.xvfb_proc = None
            self.collect_logs()
            self.write_summary("ok" if not self.failures else "failed")

    # -- outputs -----------------------------------------------------------

    def collect_logs(self):
        logs_dir = os.path.join(self.session_dir, "logs")
        os.makedirs(logs_dir, exist_ok=True)
        index = []
        for base, _dirs, files in os.walk(self.session_dir):
            if base.startswith(self.recordings_dir):
                continue
            for name in files:
                if name.endswith((".log", ".jsonl")):
                    src = os.path.join(base, name)
                    rel = os.path.relpath(src, self.session_dir)
                    dst = os.path.join(logs_dir,
                                       rel.replace(os.sep, "__"))
                    try:
                        shutil.copyfile(src, dst)
                    except OSError:
                        pass
        for name in sorted(os.listdir(self.recordings_dir)):
            path = os.path.join(self.recordings_dir, name)
            if os.path.isfile(path):
                index.append({"name": name,
                              "bytes": os.path.getsize(path)})
        try:
            with open(os.path.join(self.session_dir,
                                   "recordings_index.json"),
                      "w") as handle:
                json.dump(index, handle, indent=1)
        except OSError:
            pass

    def write_summary(self, result, detail=""):
        summary = {
            "result": result,
            "detail": detail,
            "mode": self.mode,
            "started_at": self.started_at,
            "duration_target_sec": self.duration_sec,
            "duration_actual_sec": round(
                time.time() - (self.started_at or time.time()), 1),
            "gates": self.gates,
            "failures": self.failures,
        }
        try:
            with open(os.path.join(self.session_dir,
                                   "session_summary.json"),
                      "w") as handle:
                json.dump(summary, handle, indent=1)
        except OSError:
            pass
        self.log("SESSION_RESULT %s %s gates=%s"
                 % (result, detail, self.gates))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode", default=os.environ.get("IWT_SESSION_MODE",
                                         "prepare_only"),
        choices=MODES)
    parser.add_argument(
        "--duration-sec", type=int,
        default=int(os.environ.get("IWT_SESSION_DURATION_SEC",
                                   "3300")))
    parser.add_argument(
        "--port", type=int,
        default=int(os.environ.get("IWT_DASHBOARD_PORT", "8787")))
    parser.add_argument(
        "--session-dir",
        default=os.environ.get("IWT_SESSION_DIR", ""))
    args = parser.parse_args(argv)
    if args.duration_sec > MAX_DURATION_SEC:
        print("duration %ds exceeds the %ds cap; clamping"
              % (args.duration_sec, MAX_DURATION_SEC), flush=True)
        args.duration_sec = MAX_DURATION_SEC
    if args.duration_sec < 60:
        print("duration %ds below the 60s minimum" % args.duration_sec,
              flush=True)
        return 2
    if not args.session_dir:
        stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        args.session_dir = os.path.join(ROOT, "session_output", stamp)
    args.session_dir = os.path.abspath(args.session_dir)
    os.makedirs(args.session_dir, exist_ok=True)

    session = Session(args)

    def _signal(signum, _frame):
        session.log("signal %d received; shutting down" % signum)
        session.stop_requested.set()
        session.deadline = time.monotonic()

    signal.signal(signal.SIGTERM, _signal)
    signal.signal(signal.SIGINT, _signal)
    return session.run()


if __name__ == "__main__":
    sys.exit(main())
