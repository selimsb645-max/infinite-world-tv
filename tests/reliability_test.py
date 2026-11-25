#!/usr/bin/env python3
"""Phase 09 reliability suite — Python half.

Fault-injection tests for the process supervisor
(dashboard/supervisor.py) and the log-rotation module
(dashboard/logrotate.py), using dummy units (short-lived Python
processes) in a temp runtime dir. Deterministic: the supervisor
is driven through tick() with an injected monotonic clock; only
the liveness waits are real.

Run: python3 tests/reliability_test.py
Prints PASS/FAIL lines and RELIABILITY_PY_DONE failures=N.
"""
import json
import os
import signal
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "dashboard"))

import logrotate          # noqa: E402
import supervisor as sup  # noqa: E402

failures = 0


def check(name, condition, detail=""):
    global failures
    if condition:
        print("PASS: %s%s" % (name, (" — " + detail) if detail else ""))
    else:
        failures += 1
        print("FAIL: %s%s" % (name, (" — " + detail) if detail else ""))


def wait_for(predicate, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


SLEEPER = [sys.executable, "-c", "import time; time.sleep(60)"]


def crash_script(counter_path):
    """A unit that counts its own spawns, logs a marker line, and
    exits immediately with an error — a crash loop."""
    code = (
        "import sys\n"
        "p = %r\n"
        "n = 0\n"
        "try:\n"
        "    n = int(open(p).read().strip())\n"
        "except Exception:\n"
        "    n = 0\n"
        "open(p, 'w').write(str(n + 1))\n"
        "print('crash unit marker line', flush=True)\n"
        "sys.exit(3)\n" % counter_path)
    return [sys.executable, "-c", code]


def make_supervisor(runtime, units):
    return sup.Supervisor(runtime, units)


def fast_unit(name, argv, **overrides):
    policy = {"max_restarts": 3, "window_sec": 60.0,
              "backoff_base_sec": 0.5, "backoff_factor": 2.0,
              "backoff_cap_sec": 2.0}
    policy.update(overrides)
    return sup.Unit(name, argv, **policy)


# --- log rotation --------------------------------------------------------

def test_log_rotation(tmp):
    path = os.path.join(tmp, "grow.jsonl")
    for _ in range(200):
        logrotate.append_line(path, "x" * 100 + "\n",
                              max_bytes=4096, backups=2)
    total = logrotate.total_size(path, backups=2)
    siblings = [n for n in os.listdir(tmp) if n.startswith("grow")]
    check("logrotate_bounds_total_size", total <= 4096 * 3 + 1024,
          "total=%d files=%s" % (total, sorted(siblings)))
    check("logrotate_keeps_backups_bounded", len(siblings) <= 3,
          "files=%d" % len(siblings))
    with open(path) as handle:
        lines = handle.readlines()
    check("logrotate_current_file_intact",
          len(lines) > 0 and all(len(line) == 101 for line in lines))


# --- supervisor: kill a healthy unit, expect one bounded restart ---------

def test_kill_and_restart(tmp):
    runtime = os.path.join(tmp, "rt_kill")
    unit = fast_unit("sleeper", SLEEPER)
    sv = make_supervisor(runtime, [unit])
    result = sv.start_unit("sleeper")
    check("sup_start_ok", result.get("ok") is True,
          "pid=%s" % result.get("pid"))
    dup = sv.start_unit("sleeper")
    check("sup_duplicate_start_refused",
          dup.get("ok") is False and dup.get("error") == "already_running")
    pid1 = unit.pid
    os.kill(pid1, signal.SIGKILL)
    check("sup_detects_killed_unit",
          wait_for(lambda: not sup.pid_alive(pid1)))
    now = 1000.0
    sv.tick(now)
    check("sup_enters_backoff_not_instant_restart",
          unit.state == "BACKOFF" and unit.pid is None,
          "state=%s" % unit.state)
    snapshot = unit.last_crash_snapshot
    check("sup_crash_snapshot_preserved",
          snapshot is not None and os.path.exists(snapshot))
    sv.tick(now + 0.4)  # backoff (0.5s) not yet elapsed
    check("sup_backoff_respected", unit.state == "BACKOFF")
    sv.tick(now + 0.6)
    check("sup_restarted_after_backoff",
          unit.state == "RUNNING" and unit.pid is not None
          and unit.pid != pid1 and sup.pid_alive(unit.pid),
          "new_pid=%s" % unit.pid)
    check("sup_restart_counted", unit.total_restarts == 1
          and unit.restarts_in_window(now + 0.6) == 1)
    stopped = sv.stop_unit("sleeper")
    check("sup_graceful_stop", stopped.get("ok") is True
          and not sup.pid_alive(stopped.get("stopped_pid") or -1))
    sv.tick(now + 5.0)
    check("sup_intentional_stop_not_restarted",
          unit.state == "STOPPED" and unit.total_restarts == 1)


# --- supervisor: crash loop hits the budget and STOPS ---------------------

def test_crash_loop_gives_up(tmp):
    runtime = os.path.join(tmp, "rt_crash")
    counter = os.path.join(tmp, "crash_count.txt")
    unit = fast_unit("crasher", crash_script(counter))
    sv = make_supervisor(runtime, [unit])
    sv.start_unit("crasher")
    now = 2000.0
    # Drive the supervisor: each tick either notices the exit or
    # performs the scheduled restart; the unit dies ~instantly.
    for step in range(40):
        if unit.proc is not None:
            unit.proc.wait(timeout=5)
        sv.tick(now)
        if unit.state == "BACKOFF":
            now = unit.next_restart_at + 0.01
            sv.tick(now)
        if unit.state == "FAILED":
            break
        now += 0.1
    spawns = int(open(counter).read().strip())
    check("sup_crash_loop_bounded", unit.state == "FAILED",
          "state=%s spawns=%d" % (unit.state, spawns))
    check("sup_crash_loop_spawn_count_exact",
          spawns == 1 + unit.max_restarts,
          "spawns=%d (1 initial + %d restarts)"
          % (spawns, unit.max_restarts))
    frozen = spawns
    for _ in range(5):
        sv.tick(now + 100.0)
    check("sup_failed_unit_never_restarts",
          int(open(counter).read().strip()) == frozen
          and unit.state == "FAILED")
    refused = sv.start_unit("crasher")
    check("sup_failed_unit_start_refused",
          refused.get("ok") is False
          and "operator_reset" in str(refused.get("error")))
    sv.reset_unit("crasher")
    again = sv.start_unit("crasher")
    check("sup_operator_reset_recovers", again.get("ok") is True)
    sv.stop_unit("crasher")


# --- supervisor: missing binary is a bounded failure, not a loop ---------

def test_missing_binary(tmp):
    runtime = os.path.join(tmp, "rt_missing")
    unit = fast_unit("ghost", ["/nonexistent/iwt-binary-xyz"])
    sv = make_supervisor(runtime, [unit])
    result = sv.start_unit("ghost")
    check("sup_missing_binary_reported",
          result.get("ok") is False
          and "spawn_failed" in str(result.get("error")))


# --- supervisor: one unit's failure leaves the others alone ---------------

def test_unit_independence(tmp):
    runtime = os.path.join(tmp, "rt_indep")
    counter = os.path.join(tmp, "crash_count2.txt")
    good = fast_unit("good", SLEEPER)
    bad = fast_unit("bad", crash_script(counter))
    sv = make_supervisor(runtime, [good, bad])
    sv.start_all()
    good_pid = good.pid
    now = 3000.0
    for _ in range(30):
        if bad.proc is not None:
            bad.proc.wait(timeout=5)
        sv.tick(now)
        if bad.state == "BACKOFF":
            now = bad.next_restart_at + 0.01
            sv.tick(now)
        if bad.state == "FAILED":
            break
        now += 0.1
    check("sup_units_independent",
          bad.state == "FAILED" and good.state == "RUNNING"
          and good.pid == good_pid and sup.pid_alive(good_pid),
          "good=%s bad=%s" % (good.state, bad.state))
    status = sv.status(now)
    check("sup_status_file_written",
          os.path.exists(sv.status_path)
          and status["units"]["bad"]["state"] == "FAILED"
          and status["units"]["good"]["total_restarts"] == 0)
    sv.stop_all()
    check("sup_stop_all_clean",
          not sup.pid_alive(good_pid) and good.state == "STOPPED")


# --- supervisor: second supervisor on the same runtime is refused ---------

def test_supervisor_lock(tmp):
    runtime = os.path.join(tmp, "rt_lock")
    sv1 = make_supervisor(runtime, [fast_unit("a", SLEEPER)])
    sv2 = make_supervisor(runtime, [fast_unit("a", SLEEPER)])
    check("sup_lock_first_acquires", sv1.acquire_lock() is True)
    check("sup_lock_second_refused", sv2.acquire_lock() is False)
    sv1.release_lock()
    check("sup_lock_reacquirable", sv2.acquire_lock() is True)
    sv2.release_lock()


# --- supervisor: adoption of a dashboard-started process ------------------

def test_adoption(tmp):
    runtime = os.path.join(tmp, "rt_adopt")
    os.makedirs(runtime, exist_ok=True)
    import subprocess
    proc = subprocess.Popen(SLEEPER, start_new_session=True)
    with open(os.path.join(runtime, "sleeper.pid"), "w") as handle:
        handle.write(str(proc.pid))
    unit = fast_unit("sleeper", SLEEPER)
    sv = make_supervisor(runtime, [unit])
    result = sv.start_unit("sleeper")
    check("sup_adopts_existing_process",
          result.get("ok") is True and result.get("adopted") is True
          and unit.pid == proc.pid)
    sv.stop_unit("sleeper")
    check("sup_adopted_process_stoppable",
          not sup.pid_alive(proc.pid))


def main():
    print("RELIABILITY_PY_START")
    tmp = tempfile.mkdtemp(prefix="iwt_reliability_")
    test_log_rotation(tmp)
    test_kill_and_restart(tmp)
    test_crash_loop_gives_up(tmp)
    test_missing_binary(tmp)
    test_unit_independence(tmp)
    test_supervisor_lock(tmp)
    test_adoption(tmp)
    print("RELIABILITY_PY_DONE failures=%d" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
