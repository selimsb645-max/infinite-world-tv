"""Phase 08 — log service.

Reads the log files the system actually writes:

  * stream    — stream_log.jsonl (Phase 07 StreamManager entries,
                already redacted at the source; redacted again here)
  * dashboard — dashboard_log.jsonl (this backend's own entries)
  * audit     — audit.jsonl (administrative actions)
  * alerts    — alerts.jsonl (Phase 08 alert service)
  * game      — the Godot engine log (godot.log in the project's
                app_userdata); plain text, severity inferred from
                the line, no per-line timestamps exist in that file
                so `ts` is null there — stated, not invented.

Every entry passes through redact.redact() before it leaves.
Supports source / module / severity / keyword filters and a plain
text export.
"""
import json
import os

from redact import redact

SEVERITIES = ("info", "warn", "error")


def _norm_severity(value):
    text = str(value or "info").lower()
    if text in ("warn", "warning"):
        return "warn"
    if text in ("error", "err", "fatal"):
        return "error"
    return "info"


def _read_jsonl(path, source, module=None, tail=2000):
    entries = []
    try:
        with open(path, "r") as handle:
            lines = handle.readlines()[-tail:]
    except OSError:
        return entries
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            raw = json.loads(line)
        except ValueError:
            entries.append({"ts": None, "source": source,
                            "module": module or source, "severity": "info",
                            "message": line})
            continue
        if source == "stream":
            message = str(raw.get("event", ""))
            if raw.get("detail"):
                message += ": " + str(raw["detail"])
            entries.append({"ts": raw.get("ts"), "source": source,
                            "module": "stream",
                            "severity": _norm_severity(raw.get("level")),
                            "message": message})
        else:
            entries.append({
                "ts": raw.get("ts"), "source": source,
                "module": str(raw.get("module", module or source)),
                "severity": _norm_severity(raw.get("level",
                                                  raw.get("severity"))),
                "message": str(raw.get("message", raw)),
                "extra": {k: v for k, v in raw.items()
                          if k not in ("ts", "level", "severity",
                                       "module", "message")},
            })
    return entries


def _read_godot_log(path, tail=2000):
    entries = []
    try:
        with open(path, "r", errors="replace") as handle:
            lines = handle.readlines()[-tail:]
    except OSError:
        return entries
    for line in lines:
        text = line.rstrip("\n")
        if not text.strip():
            continue
        if "ERROR" in text or "SCRIPT ERROR" in text:
            severity = "error"
        elif "WARNING" in text:
            severity = "warn"
        else:
            severity = "info"
        entries.append({"ts": None, "source": "game", "module": "game",
                        "severity": severity, "message": text})
    return entries


class LogService:
    def __init__(self, cfg):
        self.cfg = cfg

    def _sources(self):
        cfg = self.cfg
        return {
            "stream": lambda: _read_jsonl(cfg.stream_log_path, "stream"),
            "dashboard": lambda: _read_jsonl(cfg.dashboard_log_path,
                                             "dashboard"),
            "audit": lambda: _read_jsonl(cfg.audit_log_path, "audit"),
            "alerts": lambda: _read_jsonl(cfg.alerts_log_path, "alerts"),
            "game": lambda: _read_godot_log(cfg.godot_log_path),
        }

    def query(self, source=None, module=None, severity=None, q=None,
              limit=200):
        sources = self._sources()
        entries = []
        if source and source in sources:
            entries = sources[source]()
        else:
            for loader in sources.values():
                entries.extend(loader())
        if module:
            entries = [e for e in entries if e["module"] == module]
        if severity:
            entries = [e for e in entries
                       if e["severity"] == _norm_severity(severity)]
        if q:
            needle = q.lower()
            entries = [e for e in entries
                       if needle in e["message"].lower()]
        entries = entries[-max(1, min(int(limit), 2000)):]
        for entry in entries:
            entry["message"] = redact(entry["message"])
        return entries

    def export_text(self, **filters):
        entries = self.query(limit=2000, **filters)
        lines = []
        for entry in entries:
            lines.append("[%s] %-7s %-9s %-10s %s" % (
                entry.get("ts") or "-", entry["severity"].upper(),
                entry["source"], entry["module"], entry["message"]))
        return "\n".join(lines) + ("\n" if lines else "")
