"""Phase 08 — system status service.

Aggregates the dashboard overview from REAL sources only:

  * /proc/stat + /proc/meminfo + shutil.disk_usage for the host.
  * Process liveness (pidfiles + zombie-aware checks).
  * game_status.json, written every second by the Phase 08 bridge
    inside the game process from GameManager / AutonomousController
    / VideoRenderer fields.
  * stream_status.json, written every 0.5 s by the Phase 08 stream
    service from the real Phase 07 StreamAdmin.check_health()
    snapshot.
  * The recordings directory Phase 06 actually writes to.

A module that is not running is labelled STOPPED / OFFLINE /
NOT CONFIGURED — never dressed up. Streaming with no stream key in
the environment is NOT CONFIGURED: the correct, expected state.
"""
import glob
import json
import os
import shutil
import time

from process_control import pid_alive

STATUS_LABELS = ("ONLINE", "OFFLINE", "RUNNING", "STOPPED",
                 "WARNING", "ERROR", "NOT CONFIGURED")

_cpu_cache = {"at": 0.0, "value": 0.0, "sample": None}


def _read_json(path):
    try:
        with open(path, "r") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def _cpu_percent():
    now = time.time()
    if now - _cpu_cache["at"] < 1.0 and _cpu_cache["sample"] is not None:
        return _cpu_cache["value"]

    def sample():
        with open("/proc/stat", "r") as handle:
            parts = handle.readline().split()[1:]
        values = [int(p) for p in parts]
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        return sum(values), idle

    first = sample()
    time.sleep(0.15)
    second = sample()
    total_delta = second[0] - first[0]
    idle_delta = second[1] - first[1]
    value = 0.0
    if total_delta > 0:
        value = round(100.0 * (1.0 - idle_delta / total_delta), 1)
    _cpu_cache.update({"at": now, "value": value, "sample": second})
    return value


def _ram():
    info = {}
    try:
        with open("/proc/meminfo", "r") as handle:
            for line in handle:
                key, _, rest = line.partition(":")
                if key in ("MemTotal", "MemAvailable"):
                    info[key] = int(rest.split()[0])  # kB
    except OSError:
        pass
    total = info.get("MemTotal", 0) / 1024.0
    available = info.get("MemAvailable", 0) / 1024.0
    used_percent = round(100.0 * (1.0 - available / total), 1) if total else 0.0
    return {"total_mb": round(total), "available_mb": round(available),
            "used_percent": used_percent}


def _host_uptime():
    try:
        with open("/proc/uptime", "r") as handle:
            return float(handle.read().split()[0])
    except (OSError, ValueError):
        return 0.0


def _fresh(path, max_age=4.0):
    try:
        return (time.time() - os.path.getmtime(path)) <= max_age
    except OSError:
        return False


class StatusService:
    def __init__(self, cfg, control):
        self.cfg = cfg
        self.control = control

    # -- module sections -------------------------------------------------

    def _game_section(self):
        state = self.control.game_state()
        snap = _read_json(self.cfg.game_status_path)
        fresh = bool(snap) and _fresh(self.cfg.game_status_path)
        section = {"label": "STOPPED", "running": state["running"],
                   "pid": state["pid"]}
        if state["running"]:
            section["label"] = "RUNNING" if fresh else "WARNING"
        if snap:
            section["status_age_sec"] = round(
                time.time() - os.path.getmtime(self.cfg.game_status_path), 1)
            for key in ("state", "score", "mode", "world", "level_name",
                        "level_number", "level_seed", "difficulty_index",
                        "endless_active", "fps", "progress"):
                if key in snap:
                    section[key] = snap[key]
        return section, snap, fresh

    def _ai_section(self, game_label, snap):
        if game_label == "STOPPED":
            return {"label": "OFFLINE", "present": False}
        ai = (snap or {}).get("ai") or {}
        if not ai.get("present"):
            return {"label": "STOPPED", "present": False}
        section = {"label": "RUNNING" if ai.get("enabled") else "STOPPED",
                   "present": True, "enabled": bool(ai.get("enabled"))}
        stats = ai.get("stats") or {}
        for key in ("decisions", "levels_completed", "levels_attempted",
                    "success_rate", "collisions", "recoveries", "phase"):
            if key in stats:
                section[key] = stats[key]
        if "recovery_events" in ai:
            section["recovery_events"] = ai["recovery_events"]
        return section

    def _generation_section(self, game_label, snap):
        if game_label == "STOPPED":
            return {"label": "OFFLINE"}
        snap = snap or {}
        endless = bool(snap.get("endless_active"))
        return {
            "label": "RUNNING" if endless else "STOPPED",
            "endless_active": endless,
            "level_seed": snap.get("level_seed"),
            "difficulty_index": snap.get("difficulty_index"),
            "level_number": snap.get("level_number"),
            "level_name": snap.get("level_name"),
        }

    def _rendering_section(self, game_label, snap):
        recordings = {"segments": 0, "bytes": 0, "latest_ts": None}
        files = glob.glob(os.path.join(self.cfg.recordings_dir, "**", "*.mp4"),
                          recursive=True)
        recordings["segments"] = len(files)
        recordings["bytes"] = sum(os.path.getsize(f) for f in files)
        if files:
            recordings["latest_ts"] = max(os.path.getmtime(f) for f in files)
        section = {"label": "STOPPED", "recordings": recordings}
        if game_label == "STOPPED":
            section["label"] = "OFFLINE"
            return section
        broadcast = (snap or {}).get("broadcast") or {}
        if not broadcast.get("present"):
            section["label"] = "STOPPED"
            section["configured"] = False
            return section
        section["configured"] = True
        active = bool(broadcast.get("recording") or broadcast.get("continuous"))
        section["label"] = "RUNNING" if active else "STOPPED"
        section["recording"] = bool(broadcast.get("recording"))
        section["continuous"] = bool(broadcast.get("continuous"))
        section["segment_index"] = broadcast.get("segment_index")
        perf = broadcast.get("perf") or {}
        for key in ("capture_fps", "encode_fps", "frames_captured",
                    "frames_expected", "av_sync_offset"):
            if key in perf:
                section[key] = perf[key]
        section["recovery_attempts"] = broadcast.get("recovery_attempts", {})
        return section

    def _stream_section(self):
        cfg = self.cfg
        has_key = bool(os.environ.get("IWT_YOUTUBE_STREAM_KEY", "").strip())
        state = self.control.stream_state()
        snap = _read_json(cfg.stream_status_path)
        fresh = bool(snap) and _fresh(cfg.stream_status_path, max_age=3.0)
        section = {"service_running": state["running"],
                   "service_pid": state["pid"],
                   "configured": has_key}
        if not has_key and not (snap and snap.get("has_stream_key")):
            section["label"] = "NOT CONFIGURED"
        elif not state["running"]:
            section["label"] = "OFFLINE"
        elif not fresh:
            section["label"] = "WARNING"
        else:
            manager_state = snap.get("manager_state", "idle")
            section["label"] = {
                "streaming": "RUNNING",
                "recovering": "WARNING",
                "failed": "ERROR",
            }.get(manager_state, "STOPPED")
        if snap:
            section["state"] = snap.get("manager_state")
            section["visibility"] = snap.get("visibility")
            section["auto_recovery"] = snap.get("auto_recovery")
            section["config_summary"] = snap.get("config_summary")
            section["prepare"] = snap.get("prepare")
            health = snap.get("snapshot") or {}
            for key in ("active", "uptime_sec", "resolution", "target_fps",
                        "measured_fps", "target_video_kbps",
                        "measured_video_kbps", "target_audio_kbps",
                        "dropped_frames", "dup_frames", "frames_sent",
                        "ffmpeg_running", "ffmpeg_pid", "reconnect_count",
                        "network_interruptions", "last_error",
                        "last_recovery", "started_unix"):
                if key in health:
                    section[key] = health[key]
            section["reconnect_attempts"] = health.get("reconnect_attempts")
            section["status_ts"] = snap.get("ts")
        return section

    # -- aggregate ---------------------------------------------------------

    def build_status(self):
        cfg = self.cfg
        game, game_snap, _fresh_game = self._game_section()
        ai = self._ai_section(game["label"], game_snap)
        generation = self._generation_section(game["label"], game_snap)
        rendering = self._rendering_section(game["label"], game_snap)
        streaming = self._stream_section()

        health_record = _read_json(cfg.health_check_path)
        monitoring = {
            "label": "ONLINE",
            "dashboard_uptime_sec": round(time.time() - cfg.started_at, 1),
            "last_health_check": health_record,
        }

        recovery = {
            "stream_auto_recovery": streaming.get("auto_recovery"),
            "stream_reconnect_attempts": streaming.get("reconnect_attempts"),
            "stream_last_recovery": streaming.get("last_recovery"),
            "video_recovery_attempts": rendering.get("recovery_attempts", {}),
            "gameplay_recovery_events": ai.get("recovery_events"),
        }

        labels = [game["label"], ai["label"], generation["label"],
                  rendering["label"], streaming["label"]]
        if "ERROR" in labels:
            overall = "ERROR"
        elif "WARNING" in labels:
            overall = "WARNING"
        elif "RUNNING" in labels:
            overall = "ONLINE"
        else:
            overall = "OFFLINE"

        disk_path = cfg.recordings_dir if os.path.isdir(
            cfg.recordings_dir) else cfg.project_root
        disk = shutil.disk_usage(disk_path)
        return {
            "ts": time.time(),
            "overall": overall,
            "runtime": {
                "dashboard_uptime_sec": monitoring["dashboard_uptime_sec"],
                "host_uptime_sec": _host_uptime(),
                "game_state": game.get("state"),
                "stream_uptime_sec": streaming.get("uptime_sec"),
            },
            "system": {
                "cpu_percent": _cpu_percent(),
                "ram": _ram(),
                "disk": {
                    "path": disk_path,
                    "total_gb": round(disk.total / 1e9, 2),
                    "free_gb": round(disk.free / 1e9, 2),
                    "used_percent": round(100.0 * disk.used / disk.total, 1)
                    if disk.total else 0.0,
                },
            },
            "game": game,
            "ai": ai,
            "generation": generation,
            "rendering": rendering,
            "streaming": streaming,
            "monitoring": monitoring,
            "recovery": recovery,
            "last_error": streaming.get("last_error") or None,
            "last_recovery": streaming.get("last_recovery") or None,
        }

    def run_health_check(self):
        status = self.build_status()
        record = {
            "ts": time.time(),
            "overall": status["overall"],
            "modules": {
                "game": status["game"]["label"],
                "ai": status["ai"]["label"],
                "generation": status["generation"]["label"],
                "rendering": status["rendering"]["label"],
                "streaming": status["streaming"]["label"],
                "monitoring": status["monitoring"]["label"],
            },
            "cpu_percent": status["system"]["cpu_percent"],
            "ram_used_percent": status["system"]["ram"]["used_percent"],
            "disk_free_gb": status["system"]["disk"]["free_gb"],
        }
        tmp = self.cfg.health_check_path + ".tmp"
        with open(tmp, "w") as handle:
            json.dump(record, handle)
        os.replace(tmp, self.cfg.health_check_path)
        return {"ok": True, "health_check": record}
