"""Phase 08 — process control service.

Owns the two long-lived Godot service processes the dashboard
manages:

  * GameService   (res://dashboard/GameService.tscn) — the real game
    with the Phase 08 bridge; controlled day-to-day through the
    bridge's command file, started/stopped here as a process.
  * StreamService (res://dashboard/StreamService.tscn) — the
    persistent Phase 07 StreamManager/StreamAdmin pair.

Duplicate execution is prevented by pidfiles + liveness checks
(the same pid-checked lock discipline Phase 07 uses). Liveness is
zombie-aware: a reaped-but-not-waited child still answers
os.kill(pid, 0), so /proc/<pid>/stat state 'Z' counts as dead —
the exact lesson Phase 07 documented for `ps`.

Start/stop return the ACTUAL result (spawned pid, exit confirmed),
never an assumption.
"""
import json
import os
import shutil
import signal
import subprocess
import threading
import time
import uuid

from logrotate import rotate_if_needed

_cmd_locks = {"game": threading.Lock(), "stream": threading.Lock()}


def pid_alive(pid):
    if not pid or pid <= 0:
        return False
    try:
        with open("/proc/%d/stat" % pid, "r") as handle:
            state = handle.read().rsplit(")", 1)[1].split()[0]
        return state not in ("Z", "X")
    except (OSError, IndexError):
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False


def _read_pidfile(path):
    try:
        with open(path, "r") as handle:
            return int(handle.read().strip())
    except (OSError, ValueError):
        return None


def _write_pidfile(path, pid):
    with open(path, "w") as handle:
        handle.write(str(pid))


def _remove_pidfile(path):
    try:
        os.remove(path)
    except OSError:
        pass


class ProcessControl:
    def __init__(self, cfg):
        self.cfg = cfg

    # -- generic service lifecycle -------------------------------------

    def _service_state(self, pidfile):
        pid = _read_pidfile(pidfile)
        if pid is not None and pid_alive(pid):
            return {"running": True, "pid": pid}
        return {"running": False, "pid": pid}

    def _start(self, name, pidfile, argv, env_extra, log_name):
        state = self._service_state(pidfile)
        if state["running"]:
            return {"ok": False, "error": "already_running", "pid": state["pid"]}
        _remove_pidfile(pidfile)
        env = dict(os.environ)
        env.update(env_extra)
        log_path = os.path.join(self.cfg.runtime_dir, log_name)
        # Phase 09 — process logs were append-only forever; rotate
        # an oversized one before the new process appends to it.
        rotate_if_needed(log_path)
        log_handle = open(log_path, "ab")
        try:
            proc = subprocess.Popen(
                argv, cwd=self.cfg.project_root, env=env,
                stdout=log_handle, stderr=subprocess.STDOUT,
                start_new_session=True)
        except OSError as exc:
            return {"ok": False, "error": "spawn_failed:%s" % exc}
        finally:
            log_handle.close()
        _write_pidfile(pidfile, proc.pid)
        return {"ok": True, "pid": proc.pid, "service": name}

    def _stop(self, pidfile, stop_marker=None):
        pid = _read_pidfile(pidfile)
        if pid is None or not pid_alive(pid):
            _remove_pidfile(pidfile)
            return {"ok": False, "error": "not_running"}
        if stop_marker:
            with open(stop_marker, "w") as handle:
                handle.write(str(time.time()))
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except OSError:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        deadline = time.time() + 5.0
        while time.time() < deadline and pid_alive(pid):
            time.sleep(0.1)
        if pid_alive(pid):
            try:
                os.killpg(os.getpgid(pid), signal.SIGKILL)
            except OSError:
                pass
            deadline = time.time() + 2.0
            while time.time() < deadline and pid_alive(pid):
                time.sleep(0.1)
        _remove_pidfile(pidfile)
        if pid_alive(pid):
            return {"ok": False, "error": "process_did_not_exit", "pid": pid}
        return {"ok": True, "stopped_pid": pid}

    # -- game service ----------------------------------------------------

    def game_state(self):
        return self._service_state(self.cfg.game_pidfile)

    def start_game(self):
        if not self.cfg.godot_bin:
            return {"ok": False, "error": "godot_binary_not_found"}
        try:
            os.remove(self.cfg.game_stop_marker)
        except OSError:
            pass
        argv = self._game_argv()
        if argv is None:
            return {"ok": False, "error": "no_display_and_no_xvfb"}
        return self._start("game", self.cfg.game_pidfile, argv,
                           {"IWT_DASHBOARD_DIR": self.cfg.game_rt_dir},
                           "game_process.log")

    def _game_argv(self):
        godot = self.cfg.godot_bin
        scene = ["--path", self.cfg.game_dir, "res://dashboard/GameService.tscn"]
        mode = self.cfg.game_display_mode
        if mode == "headless":
            return [godot, "--headless"] + scene
        if mode == "windowed":
            return [godot] + scene
        # auto: real display if present, else Xvfb, else headless.
        if os.environ.get("DISPLAY"):
            return [godot] + scene
        xvfb = shutil.which("xvfb-run")
        if xvfb:
            return [xvfb, "-a", godot] + scene
        return [godot, "--headless"] + scene

    def stop_game(self):
        return self._stop(self.cfg.game_pidfile, self.cfg.game_stop_marker)

    def restart_game(self):
        stopped = self.stop_game()
        started = self.start_game()
        return {"ok": started.get("ok", False), "stop": stopped,
                "start": started}

    # -- stream service ----------------------------------------------------

    def stream_state(self):
        return self._service_state(self.cfg.stream_pidfile)

    def start_stream_service(self):
        if not self.cfg.godot_bin:
            return {"ok": False, "error": "godot_binary_not_found"}
        argv = [self.cfg.godot_bin, "--headless", "--path", self.cfg.game_dir,
                "res://dashboard/StreamService.tscn"]
        return self._start("stream", self.cfg.stream_pidfile, argv,
                           {"IWT_STREAM_RUNTIME_DIR": self.cfg.stream_rt_dir},
                           "stream_process.log")

    def stop_stream_service(self):
        # Prefer the service's own graceful quit (StreamAdmin stop +
        # clean exit); fall back to process termination.
        state = self.stream_state()
        if state["running"]:
            result = self.send_stream_cmd("quit", {}, timeout=6.0)
            deadline = time.time() + 3.0
            while time.time() < deadline and pid_alive(state["pid"]):
                time.sleep(0.1)
            if not pid_alive(state["pid"]):
                _remove_pidfile(self.cfg.stream_pidfile)
                return {"ok": True, "stopped_pid": state["pid"],
                        "via": "quit_command", "quit_result": result}
        return self._stop(self.cfg.stream_pidfile)

    def restart_stream_service(self):
        stopped = self.stop_stream_service()
        started = self.start_stream_service()
        return {"ok": started.get("ok", False), "stop": stopped,
                "start": started}

    # -- command-file round trips -------------------------------------------

    def send_game_cmd(self, action, params=None, timeout=12.0):
        if not self.game_state()["running"]:
            return {"ok": False, "error": "game_not_running"}
        return self._send_cmd("game", self.cfg.game_rt_dir,
                              "game_cmd.json", "game_result_%s.json",
                              action, params or {}, timeout)

    def send_stream_cmd(self, action, extra=None, timeout=12.0):
        if not self.stream_state()["running"]:
            return {"ok": False, "error": "stream_service_not_running"}
        return self._send_cmd("stream", self.cfg.stream_rt_dir,
                              "stream_cmd.json", "stream_result_%s.json",
                              action, extra or {}, timeout)

    def _send_cmd(self, target, rt_dir, cmd_name, result_pattern,
                  action, extra, timeout):
        with _cmd_locks[target]:
            cmd_id = uuid.uuid4().hex[:12]
            payload = {"id": cmd_id, "action": action}
            payload.update(extra)
            cmd_path = os.path.join(rt_dir, cmd_name)
            tmp_path = cmd_path + ".tmp"
            with open(tmp_path, "w") as handle:
                json.dump(payload, handle)
            os.replace(tmp_path, cmd_path)
            result_path = os.path.join(rt_dir, result_pattern % cmd_id)
            deadline = time.time() + timeout
            while time.time() < deadline:
                if os.path.exists(result_path):
                    try:
                        with open(result_path, "r") as handle:
                            data = json.load(handle)
                    except (OSError, ValueError):
                        time.sleep(0.05)
                        continue
                    try:
                        os.remove(result_path)
                    except OSError:
                        pass
                    return data.get("result", data)
                time.sleep(0.05)
            return {"ok": False, "error": "command_timeout",
                    "action": action}
