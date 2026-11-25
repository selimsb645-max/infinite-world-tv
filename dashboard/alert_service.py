"""Phase 08 — alert service.

Evaluates REAL conditions from the aggregated status every
`interval` seconds and appends transitions to alerts.jsonl:

  stream_failed        stream manager reached FAILED (error)
  stream_disconnect    network interruption counter increased (warn)
  cpu_high / ram_high  host usage above 90% (warn)
  recovery_repeated    stream reconnect attempts >= 3 (warn)
  disk_low             recordings disk >90% used (warn), >95% (error)
  config_error         stream service running but prepare reported
                       validation errors (warn)
  game_crash           game process died without a dashboard stop
                       request (error)

Free and local only: alerts land in a JSONL file the dashboard
serves. Optional outbound hooks (webhook URL / email) are NOT
implemented — see docs/PHASE08.md; no paid service is involved.

State transitions are the dedupe: a condition writes once when it
becomes active and once when it resolves, never on every tick.
"""
import json
import os
import threading
import time

from redact import redact_obj


class AlertService:
    def __init__(self, cfg, status_service, control, interval=15.0):
        self.cfg = cfg
        self.status_service = status_service
        self.control = control
        self.interval = interval
        self._active = {}
        self._last_interruptions = None
        self._game_was_running = False
        self._thread = None
        self._stopped = threading.Event()

    def start(self):
        self._thread = threading.Thread(target=self._loop, daemon=True,
                                        name="iwt-alerts")
        self._thread.start()

    def stop(self):
        self._stopped.set()

    def _loop(self):
        while not self._stopped.wait(self.interval):
            try:
                self.evaluate_once()
            except Exception:
                # The monitor must never take the dashboard down.
                pass

    def _append(self, key, severity, message, state):
        entry = {"ts": time.time(), "level": severity, "module": "alerts",
                 "key": key, "state": state, "message": message}
        with open(self.cfg.alerts_log_path, "a") as handle:
            handle.write(json.dumps(redact_obj(entry)) + "\n")

    def _set(self, key, severity, message, active):
        was_active = key in self._active
        if active and not was_active:
            self._active[key] = severity
            self._append(key, severity, message, "active")
        elif not active and was_active:
            del self._active[key]
            self._append(key, "info", message + " (resolved)", "resolved")

    def evaluate_once(self):
        status = self.status_service.build_status()
        streaming = status["streaming"]
        system = status["system"]

        self._set("stream_failed", "error",
                  "Streaming manager state is FAILED",
                  streaming.get("state") == "failed")
        self._set("cpu_high", "warn", "CPU usage above 90%",
                  system["cpu_percent"] > 90.0)
        self._set("ram_high", "warn", "RAM usage above 90%",
                  system["ram"]["used_percent"] > 90.0)
        attempts = streaming.get("reconnect_attempts") or 0
        self._set("recovery_repeated", "warn",
                  "Stream reconnect attempts reached %d" % attempts,
                  attempts >= 3)
        used = system["disk"]["used_percent"]
        self._set("disk_low", "error" if used > 95.0 else "warn",
                  "Recordings disk %.1f%% used" % used, used > 90.0)
        prepare = streaming.get("prepare") or {}
        errors = prepare.get("errors") or []
        self._set("config_error", "warn",
                  "Stream configuration errors: %s" % ", ".join(errors),
                  bool(streaming.get("service_running")) and bool(errors))

        interruptions = streaming.get("network_interruptions")
        if interruptions is not None:
            if (self._last_interruptions is not None
                    and interruptions > self._last_interruptions):
                self._append("stream_disconnect", "warn",
                             "Stream network interruption count rose to %d"
                             % interruptions, "event")
            self._last_interruptions = interruptions

        game = status["game"]
        crashed = (self._game_was_running and not game["running"]
                   and not os.path.exists(self.cfg.game_stop_marker))
        self._set("game_crash", "error",
                  "Game process exited unexpectedly", bool(crashed))
        if game["running"]:
            self._game_was_running = True
        elif crashed:
            self._game_was_running = False
        return status

    def active_alerts(self):
        return [{"key": key, "severity": severity}
                for key, severity in sorted(self._active.items())]
