#!/usr/bin/env python3
"""Phase 09 — process supervisor for INFINITE WORLD TV.

Why this exists (Phase 09 audit finding #1): before this module,
NOTHING restarted a dead host process. Phase 07's bounded
reconnect lives INSIDE the StreamService Godot process — if that
process itself dies, the recovery logic dies with it. The Phase 08
dashboard can start/stop the game and stream services and its
alert service can *notice* a crash, but no component acted.

This supervisor owns the three long-lived processes:

  game       Godot GameService scene (the real game + bridge)
  stream     Godot StreamService scene (Phase 07 StreamManager)
  dashboard  the Phase 08 backend (dashboard/server.py)

Policy per unit (configurable):
  * Unexpected exit -> the tail of the unit's log is preserved to
    crashes/<unit>_<timestamp>.log BEFORE any restart, then the
    unit is restarted after an exponential backoff
    (base * factor**attempt, capped).
  * At most max_restarts restarts inside window_sec; past that
    the unit is FAILED and is NOT restarted again until an
    operator intervenes. There is no code path that loops
    restarts without bound.
  * Duplicate execution is refused twice over: the supervisor
    itself takes a pid-checked lock for the runtime dir, and each
    unit uses the same pidfile the Phase 08 dashboard uses, so
    the dashboard and the supervisor agree on what is running
    (a unit started by the dashboard is adopted and supervised,
    not double-started).
  * Intentional stops are never counted as crashes and never
    restarted. Stopping the game also writes the dashboard's
    stop marker, so its crash alert does not fire.
  * Graceful shutdown: SIGTERM to every unit's process group,
    a bounded wait, SIGKILL as the last resort.
  * A failure in one unit never touches the others: units are
    supervised independently.

State is observable: supervisor_status.json (rewritten on every
tick) and supervisor.jsonl (rotated, bounded) live in the runtime
dir. Python 3 standard library only.

Usage:
  python3 dashboard/supervisor.py [--runtime DIR] [--godot PATH]
                              [--units game,stream,dashboard]
  python3 dashboard/supervisor.py --status   # print status JSON
"""
import argparse
import json
import os
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(HERE)

LOG_MAX_BYTES = 5 * 1024 * 1024
LOG_BACKUPS = 3
CRASH_SNAPSHOTS_KEPT = 5
CRASH_TAIL_LINES = 200


# -- small shared helpers (kept local: the supervisor must not
#    depend on the dashboard package it supervises) ----------------

def pid_alive(pid):
    """Zombie-aware liveness (same lesson as Phase 07/08)."""
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


def _rotate(path, max_bytes=LOG_MAX_BYTES, backups=LOG_BACKUPS):
    try:
        if os.path.getsize(path) < max_bytes:
            return
        oldest = "%s.%d" % (path, backups)
        if os.path.exists(oldest):
            os.remove(oldest)
        for index in range(backups - 1, 0, -1):
            src = "%s.%d" % (path, index)
            if os.path.exists(src):
                os.replace(src, "%s.%d" % (path, index + 1))
        os.replace(path, "%s.1" % path)
    except OSError:
        pass


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


class Unit:
    """One supervised process and its restart policy."""

    def __init__(self, name, argv, env=None, log_name=None,
                 pidfile_name=None, stop_marker=None,
                 max_restarts=5, window_sec=600.0,
                 backoff_base_sec=2.0, backoff_factor=2.0,
                 backoff_cap_sec=60.0):
        self.name = name
        self.argv = argv
        self.env = env or {}
        self.log_name = log_name or ("%s_process.log" % name)
        self.pidfile_name = pidfile_name or ("%s.pid" % name)
        self.stop_marker = stop_marker
        self.max_restarts = max_restarts
        self.window_sec = window_sec
        self.backoff_base_sec = backoff_base_sec
        self.backoff_factor = backoff_factor
        self.backoff_cap_sec = backoff_cap_sec
        # runtime state
        self.state = "STOPPED"  # STOPPED RUNNING BACKOFF FAILED STOPPING
        self.pid = None
        self.proc = None
        self.restart_times = []       # monotonic timestamps in window
        self.total_restarts = 0
        self.next_restart_at = None   # monotonic deadline for BACKOFF
        self.last_exit = None         # {"ts", "code"} of last exit
        self.last_crash_snapshot = None
        self.started_by_us = False

    def backoff_delay(self, attempt_index):
        delay = self.backoff_base_sec * (
            self.backoff_factor ** max(0, attempt_index - 1))
        return min(delay, self.backoff_cap_sec)

    def restarts_in_window(self, now):
        cutoff = now - self.window_sec
        self.restart_times = [t for t in self.restart_times
                              if t > cutoff]
        return len(self.restart_times)

    def status(self, now):
        return {
            "name": self.name,
            "state": self.state,
            "pid": self.pid,
            "restarts_in_window": self.restarts_in_window(now),
            "total_restarts": self.total_restarts,
            "max_restarts": self.max_restarts,
            "window_sec": self.window_sec,
            "last_exit": self.last_exit,
            "last_crash_snapshot": self.last_crash_snapshot,
        }


class Supervisor:
    def __init__(self, runtime_dir, units):
        self.runtime_dir = runtime_dir
        self.units = {unit.name: unit for unit in units}
        self.log_path = os.path.join(runtime_dir, "supervisor.jsonl")
        self.status_path = os.path.join(runtime_dir,
                                        "supervisor_status.json")
        self.lock_path = os.path.join(runtime_dir, "supervisor.lock")
        self.crash_dir = os.path.join(runtime_dir, "crashes")
        self._lock_held = False
        self._stopping = False
        os.makedirs(runtime_dir, exist_ok=True)
        os.makedirs(self.crash_dir, exist_ok=True)

    # -- supervisor's own lock -------------------------------------

    def acquire_lock(self):
        holder = _read_pidfile(self.lock_path)
        # Refuse when a live process holds the lock and it is not
        # THIS instance re-acquiring its own. (Comparing only the
        # pid would let two Supervisor objects in one process —
        # e.g. tests, or an embedding app — both believe they hold
        # it; the _lock_held flag is the instance-level truth.)
        if holder is not None and pid_alive(holder) \
                and not self._lock_held:
            return False
        _write_pidfile(self.lock_path, os.getpid())
        self._lock_held = True
        return True

    def release_lock(self):
        if self._lock_held:
            _remove_pidfile(self.lock_path)
            self._lock_held = False

    # -- logging -----------------------------------------------------

    def log(self, level, event, detail=""):
        entry = {"ts": time.time(), "level": level, "module": "supervisor",
                 "event": event, "detail": detail}
        _rotate(self.log_path)
        try:
            with open(self.log_path, "a") as handle:
                handle.write(json.dumps(entry) + "\n")
        except OSError:
            pass

    # -- unit lifecycle ----------------------------------------------

    def _unit_log_path(self, unit):
        return os.path.join(self.runtime_dir, unit.log_name)

    def _unit_pidfile(self, unit):
        return os.path.join(self.runtime_dir, unit.pidfile_name)

    def _spawn(self, unit):
        env = dict(os.environ)
        env.update(unit.env)
        log_path = self._unit_log_path(unit)
        _rotate(log_path)
        log_handle = open(log_path, "ab")
        try:
            proc = subprocess.Popen(
                unit.argv, cwd=PROJECT_ROOT, env=env,
                stdout=log_handle, stderr=subprocess.STDOUT,
                start_new_session=True)
        except OSError as exc:
            log_handle.close()
            return {"ok": False, "error": "spawn_failed:%s" % exc}
        log_handle.close()
        unit.proc = proc
        unit.pid = proc.pid
        unit.state = "RUNNING"
        unit.started_by_us = True
        _write_pidfile(self._unit_pidfile(unit), proc.pid)
        return {"ok": True, "pid": proc.pid}

    def _adopt_or_spawn(self, unit):
        """Start a unit, adopting a live process the pidfile names
        (e.g. one the dashboard started) instead of duplicating."""
        pid = _read_pidfile(self._unit_pidfile(unit))
        if pid is not None and pid_alive(pid):
            if unit.pid == pid and unit.state == "RUNNING":
                return {"ok": False, "error": "already_running",
                        "pid": pid}
            unit.pid = pid
            unit.proc = None
            unit.state = "RUNNING"
            unit.started_by_us = False
            self.log("info", "unit_adopted",
                     "%s pid=%d (started elsewhere)" % (unit.name, pid))
            return {"ok": True, "pid": pid, "adopted": True}
        if unit.state == "RUNNING" and unit.pid and pid_alive(unit.pid):
            return {"ok": False, "error": "already_running",
                    "pid": unit.pid}
        return self._spawn(unit)

    def start_unit(self, name):
        unit = self.units[name]
        if unit.state == "FAILED":
            return {"ok": False, "error": "unit_failed_operator_reset_required"}
        if unit.state in ("RUNNING", "BACKOFF"):
            return {"ok": False, "error": "already_running",
                    "pid": unit.pid}
        result = self._adopt_or_spawn(unit)
        if result.get("ok"):
            self.log("info", "unit_started",
                     "%s pid=%s" % (name, result.get("pid")))
        else:
            self.log("error", "unit_start_failed",
                     "%s %s" % (name, result.get("error")))
        self.write_status()
        return result

    def stop_unit(self, name, graceful_sec=5.0):
        unit = self.units[name]
        unit.state = "STOPPING"
        pid = unit.pid or _read_pidfile(self._unit_pidfile(unit))
        if unit.stop_marker:
            try:
                with open(os.path.join(self.runtime_dir,
                                       unit.stop_marker), "w") as handle:
                    handle.write(str(time.time()))
            except OSError:
                pass
        if pid is None or not pid_alive(pid):
            unit.pid = None
            unit.proc = None
            unit.state = "STOPPED"
            _remove_pidfile(self._unit_pidfile(unit))
            self.write_status()
            return {"ok": True, "was_running": False}
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except OSError:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        deadline = time.time() + graceful_sec
        while time.time() < deadline and pid_alive(pid):
            time.sleep(0.05)
        if pid_alive(pid):
            try:
                os.killpg(os.getpgid(pid), signal.SIGKILL)
            except OSError:
                pass
            deadline = time.time() + 2.0
            while time.time() < deadline and pid_alive(pid):
                time.sleep(0.05)
        stopped = not pid_alive(pid)
        unit.pid = None
        unit.proc = None
        unit.state = "STOPPED"
        _remove_pidfile(self._unit_pidfile(unit))
        self.log("info", "unit_stopped", "%s pid=%d" % (name, pid))
        self.write_status()
        return {"ok": stopped, "was_running": True, "stopped_pid": pid}

    def reset_unit(self, name):
        """Operator reset of a FAILED unit: clears the restart
        window so start_unit works again."""
        unit = self.units[name]
        unit.restart_times = []
        if unit.state == "FAILED":
            unit.state = "STOPPED"
        self.log("info", "unit_reset", name)
        self.write_status()
        return {"ok": True}

    # -- supervision ---------------------------------------------------

    def _unit_alive(self, unit):
        if unit.proc is not None:
            return unit.proc.poll() is None
        if unit.pid:
            return pid_alive(unit.pid)
        return False

    def _exit_code(self, unit):
        if unit.proc is not None:
            return unit.proc.poll()
        return None  # adopted process: exit code unknowable

    def _snapshot_crash(self, unit):
        """Preserve the tail of the unit's log BEFORE restarting."""
        log_path = self._unit_log_path(unit)
        try:
            with open(log_path, "rb") as handle:
                lines = handle.readlines()[-CRASH_TAIL_LINES:]
        except OSError:
            lines = []
        stamp = time.strftime("%Y%m%d_%H%M%S", time.localtime())
        path = os.path.join(self.crash_dir,
                            "%s_%s.log" % (unit.name, stamp))
        try:
            with open(path, "wb") as handle:
                handle.write(
                    ("# crash snapshot: unit=%s pid=%s exit=%s ts=%s\n"
                     % (unit.name, unit.pid, unit.last_exit,
                        stamp)).encode())
                for line in lines:
                    handle.write(line)
        except OSError:
            return None
        unit.last_crash_snapshot = path
        # Keep only the newest snapshots for this unit.
        try:
            siblings = sorted(
                name for name in os.listdir(self.crash_dir)
                if name.startswith(unit.name + "_"))
            for stale in siblings[:-CRASH_SNAPSHOTS_KEPT]:
                os.remove(os.path.join(self.crash_dir, stale))
        except OSError:
            pass
        return path

    def tick(self, now=None):
        """One supervision pass. Driven by run(); tests call it
        directly with an injected clock for determinism."""
        now = time.monotonic() if now is None else now
        for unit in self.units.values():
            if unit.state == "RUNNING":
                if not self._unit_alive(unit):
                    self._on_unexpected_exit(unit, now)
            elif unit.state == "BACKOFF":
                if unit.next_restart_at is not None \
                        and now >= unit.next_restart_at:
                    unit.next_restart_at = None
                    result = self._spawn(unit)
                    if result.get("ok"):
                        unit.total_restarts += 1
                        self.log("warn", "unit_restarted",
                                 "%s pid=%d (restart %d in window)"
                                 % (unit.name, result["pid"],
                                    unit.restarts_in_window(now)))
                    else:
                        self._on_unexpected_exit(unit, now)
        self.write_status(now)
        return self.status(now)

    def _on_unexpected_exit(self, unit, now):
        code = self._exit_code(unit)
        unit.last_exit = {"ts": time.time(), "code": code}
        dead_pid = unit.pid
        unit.pid = None
        unit.proc = None
        _remove_pidfile(self._unit_pidfile(unit))
        snapshot = self._snapshot_crash(unit)
        self.log("error", "unit_exited",
                 "%s pid=%s exit=%s snapshot=%s"
                 % (unit.name, dead_pid, code, snapshot))
        if self._stopping:
            unit.state = "STOPPED"
            return
        in_window = unit.restarts_in_window(now)
        if in_window >= unit.max_restarts:
            unit.state = "FAILED"
            self.log("error", "unit_failed",
                     "%s exhausted %d restarts in %.0fs window; "
                     "operator reset required"
                     % (unit.name, unit.max_restarts, unit.window_sec))
            return
        unit.restart_times.append(now)
        delay = unit.backoff_delay(len(unit.restart_times))
        unit.next_restart_at = now + delay
        unit.state = "BACKOFF"
        self.log("warn", "unit_restart_scheduled",
                 "%s restart %d/%d in %.1fs"
                 % (unit.name, len(unit.restart_times),
                    unit.max_restarts, delay))

    # -- whole-supervisor lifecycle -------------------------------------

    def start_all(self):
        results = {}
        for name in self.units:
            results[name] = self.start_unit(name)
        return results

    def stop_all(self):
        self._stopping = True
        results = {}
        for name in self.units:
            results[name] = self.stop_unit(name)
        self.write_status()
        return results

    def status(self, now=None):
        now = time.monotonic() if now is None else now
        return {
            "ts": time.time(),
            "supervisor_pid": os.getpid(),
            "units": {name: unit.status(now)
                      for name, unit in self.units.items()},
        }

    def write_status(self, now=None):
        try:
            tmp = self.status_path + ".tmp"
            with open(tmp, "w") as handle:
                json.dump(self.status(now), handle, indent=1)
            os.replace(tmp, self.status_path)
        except OSError:
            pass

    def run(self, poll_sec=0.5):
        if not self.acquire_lock():
            self.log("error", "lock_refused",
                     "another supervisor holds %s" % self.lock_path)
            return 3
        self.log("info", "supervisor_started",
                 "units=%s" % ",".join(sorted(self.units)))
        try:
            self.start_all()
            while not self._stopping:
                self.tick()
                time.sleep(poll_sec)
        except KeyboardInterrupt:
            pass
        finally:
            self.stop_all()
            self.release_lock()
            self.log("info", "supervisor_stopped", "")
        return 0


# -- default unit construction -----------------------------------------

def default_units(godot_bin, runtime_dir, only=None):
    game_rt = os.path.join(runtime_dir, "game")
    stream_rt = os.path.join(runtime_dir, "stream")
    units = [
        Unit(
            "game",
            [godot_bin, "--headless", "--path",
             os.path.join(PROJECT_ROOT, "game"),
             "res://dashboard/GameService.tscn"],
            env={"IWT_DASHBOARD_DIR": game_rt},
            log_name="game_process.log",
            pidfile_name="game.pid",
            stop_marker="game.stop_requested"),
        Unit(
            "stream",
            [godot_bin, "--headless", "--path",
             os.path.join(PROJECT_ROOT, "game"),
             "res://dashboard/StreamService.tscn"],
            env={"IWT_STREAM_RUNTIME_DIR": stream_rt},
            log_name="stream_process.log",
            pidfile_name="stream.pid"),
        Unit(
            "dashboard",
            [sys.executable,
             os.path.join(PROJECT_ROOT, "dashboard", "server.py")],
            env={"IWT_DASHBOARD_RUNTIME": runtime_dir},
            log_name="dashboard_stdout.log",
            pidfile_name="dashboard.pid"),
    ]
    if only:
        wanted = set(only)
        units = [unit for unit in units if unit.name in wanted]
    return units


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", default=os.environ.get(
        "IWT_DASHBOARD_RUNTIME",
        os.path.join(PROJECT_ROOT, "dashboard", "runtime")))
    parser.add_argument("--godot", default=os.environ.get(
        "IWT_GODOT_BIN", "") or "godot")
    parser.add_argument("--units", default="",
                        help="comma list; default all three")
    parser.add_argument("--status", action="store_true",
                        help="print supervisor_status.json and exit")
    args = parser.parse_args(argv)
    if args.status:
        path = os.path.join(args.runtime, "supervisor_status.json")
        try:
            with open(path, "r") as handle:
                print(handle.read())
            return 0
        except OSError:
            print(json.dumps({"units": {}, "error": "no_status_file"}))
            return 1
    only = [name.strip() for name in args.units.split(",") if name.strip()]
    supervisor = Supervisor(
        args.runtime, default_units(args.godot, args.runtime, only))

    def _sigterm(_signum, _frame):
        supervisor.stop_all()
        supervisor.release_lock()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, _sigterm)
    signal.signal(signal.SIGINT, _sigterm)
    return supervisor.run()


if __name__ == "__main__":
    sys.exit(main())
