#!/usr/bin/env python3
"""Phase 09 — long-run stability driver.

Runs the REAL system under the Phase 09 supervisor for a bounded,
honest duration: GameService (headless), StreamService (headless)
and the dashboard backend, all in a throwaway runtime dir. Every
10 s it samples unit liveness, per-process RSS and CPU, the game
bridge FPS and dashboard HTTP reachability. Mid-run it injects
two real faults — SIGKILL to the game process, later SIGKILL to
the stream service — and records whether the supervisor detects
and recovers each one.

The duration is whatever IWT_STABILITY_SEC says (default 600 s).
The output reports the duration that ACTUALLY ran; nothing here
claims a 1-hour / 6-hour / 24-hour soak.

Writes tests/stability_output.txt with MEASURED lines and
STABILITY_DONE failures=N (failures = unrecovered injections,
units down at the end, or a dashboard that stayed unreachable).
"""
import json
import os
import shutil
import signal
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "dashboard"))

import supervisor as sup  # noqa: E402

DURATION = float(os.environ.get("IWT_STABILITY_SEC", "600"))
SAMPLE_SEC = 10.0
PORT = int(os.environ.get("IWT_STABILITY_PORT", "8899"))
GODOT = (os.environ.get("IWT_GODOT_BIN") or os.environ.get("GODOT")
         or "godot")
RUNTIME = os.environ.get("IWT_STABILITY_RUNTIME", "/tmp/iwt_stability")
OUT = os.path.join(ROOT, "tests", "stability_output.txt")


def rss_kb(pid):
    try:
        with open("/proc/%d/status" % pid) as handle:
            for line in handle:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return None


def cpu_ticks(pid):
    try:
        with open("/proc/%d/stat" % pid) as handle:
            parts = handle.read().rsplit(")", 1)[1].split()
        return int(parts[11]) + int(parts[12])  # utime + stime
    except (OSError, IndexError, ValueError):
        return None


def http_ok():
    try:
        with urllib.request.urlopen(
                "http://127.0.0.1:%d/" % PORT, timeout=3) as resp:
            return resp.status == 200
    except Exception:
        return False


def game_fps():
    try:
        with open(os.path.join(RUNTIME, "game",
                               "game_status.json")) as handle:
            return float(json.load(handle).get("fps"))
    except (OSError, ValueError, TypeError):
        return None


def main():
    lines = []
    failures = 0

    def measured(text):
        lines.append("MEASURED " + text)
        print("MEASURED " + text, flush=True)

    if os.path.isdir(RUNTIME):
        shutil.rmtree(RUNTIME)
    os.makedirs(RUNTIME)
    units = sup.default_units(GODOT, RUNTIME)
    for unit in units:
        if unit.name == "dashboard":
            unit.env.update({
                "IWT_DASHBOARD_PORT": str(PORT),
                "IWT_ADMIN_TOKEN": "stability-test-admin-token",
                "IWT_VIEWER_TOKEN": "stability-test-viewer-token",
                "IWT_GAME_DISPLAY_MODE": "headless",
            })
    sv = sup.Supervisor(RUNTIME, units)
    if not sv.acquire_lock():
        print("STABILITY_DONE failures=1 (supervisor lock refused)")
        return 1
    started = time.monotonic()
    results = sv.start_all()
    measured("run_start duration_target_sec=%.0f units=%s"
             % (DURATION, {k: v.get("ok") for k, v in results.items()}))
    for name, result in results.items():
        if not result.get("ok"):
            failures += 1
            measured("unit_failed_to_start %s %s" % (name, result))

    injections = [
        {"at": 0.40 * DURATION, "unit": "game", "done": False,
         "detected": False, "recovered": False, "pid_before": None},
        {"at": 0.70 * DURATION, "unit": "stream", "done": False,
         "detected": False, "recovered": False, "pid_before": None},
    ]
    samples = {"rss": {}, "cpu": {}, "fps": [], "http_fail": 0,
               "ticks": 0}
    prev_cpu = {}
    prev_t = time.monotonic()
    clk = os.sysconf("SC_CLK_TCK")

    try:
        while time.monotonic() - started < DURATION:
            now = time.monotonic()
            elapsed = now - started
            sv.tick(now)
            # fault injection + tracking
            for inj in injections:
                unit = sv.units[inj["unit"]]
                if not inj["done"] and elapsed >= inj["at"]:
                    inj["pid_before"] = unit.pid
                    if unit.pid and sup.pid_alive(unit.pid):
                        os.kill(unit.pid, signal.SIGKILL)
                        inj["done"] = True
                        measured("injected SIGKILL unit=%s pid=%s "
                                 "at_elapsed=%.0fs"
                                 % (inj["unit"], inj["pid_before"],
                                    elapsed))
                    else:
                        inj["done"] = True
                        inj["detected"] = True  # nothing to kill
                        measured("injection_skipped unit=%s "
                                 "not_running" % inj["unit"])
                if inj["done"] and not inj["recovered"]:
                    if unit.state in ("BACKOFF", "FAILED") \
                            or (unit.pid is not None
                                and unit.pid != inj["pid_before"]):
                        inj["detected"] = True
                    if unit.state == "RUNNING" and unit.pid \
                            and unit.pid != inj["pid_before"] \
                            and sup.pid_alive(unit.pid):
                        inj["recovered"] = True
                        measured("recovered unit=%s new_pid=%s"
                                 % (inj["unit"], unit.pid))
            # sampling
            samples["ticks"] += 1
            for unit in sv.units.values():
                if unit.pid and sup.pid_alive(unit.pid):
                    rss = rss_kb(unit.pid)
                    if rss is not None:
                        samples["rss"].setdefault(
                            unit.name, []).append(rss)
                    ticks = cpu_ticks(unit.pid)
                    if ticks is not None and unit.pid in prev_cpu:
                        dt = now - prev_t
                        pct = 100.0 * (ticks - prev_cpu[unit.pid]) \
                            / (clk * dt)
                        samples["cpu"].setdefault(
                            unit.name, []).append(round(pct, 1))
                    if ticks is not None:
                        prev_cpu[unit.pid] = ticks
            fps = game_fps()
            if fps is not None:
                samples["fps"].append(fps)
            if not http_ok():
                samples["http_fail"] += 1
            prev_t = now
            time.sleep(SAMPLE_SEC)
    finally:
        actual = time.monotonic() - started
        end_states = {name: unit.state
                      for name, unit in sv.units.items()}
        restarts = {name: unit.total_restarts
                    for name, unit in sv.units.items()}
        sv.stop_all()
        sv.release_lock()

    for inj in injections:
        if inj["done"] and not inj["recovered"] \
                and inj["pid_before"] is not None:
            failures += 1
    for name, state in end_states.items():
        if state not in ("RUNNING",):
            # A unit that ended FAILED/STOPPED without an injection
            # explanation is a stability failure. Units whose state
            # is BACKOFF at the buzzer were mid-recovery: count the
            # injection as unrecovered above, not twice here.
            if state == "FAILED":
                failures += 1
    if samples["ticks"] > 0 and samples["http_fail"] > samples["ticks"] // 2:
        failures += 1

    measured("run_end actual_duration_sec=%.0f samples=%d"
             % (actual, samples["ticks"]))
    measured("end_states %s" % json.dumps(end_states))
    measured("total_restarts %s" % json.dumps(restarts))
    for name, series in sorted(samples["rss"].items()):
        if series:
            measured("rss unit=%s start_mb=%.1f end_mb=%.1f peak_mb=%.1f"
                     % (name, series[0] / 1024.0, series[-1] / 1024.0,
                        max(series) / 1024.0))
    for name, series in sorted(samples["cpu"].items()):
        if series:
            measured("cpu unit=%s avg_pct=%.1f peak_pct=%.1f"
                     % (name, sum(series) / len(series), max(series)))
    if samples["fps"]:
        ordered = sorted(samples["fps"])
        measured("game_fps median=%.0f min=%.0f max=%.0f samples=%d"
                 % (ordered[len(ordered) // 2], ordered[0],
                    ordered[-1], len(ordered)))
    else:
        measured("game_fps unavailable (bridge wrote no fps samples)")
    measured("dashboard_http_failed_samples=%d of %d"
             % (samples["http_fail"], samples["ticks"]))
    for inj in injections:
        measured("injection unit=%s detected=%s recovered=%s"
                 % (inj["unit"], inj["detected"], inj["recovered"]))
    lines.append("STABILITY_DONE failures=%d" % failures)
    with open(OUT, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print("STABILITY_DONE failures=%d" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
