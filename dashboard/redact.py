"""Phase 08 — secret redaction for everything the dashboard emits.

Mirrors the Phase 07 rule: the YouTube stream key and the admin /
viewer tokens must never appear in a status payload, a log line, an
alert or an audit entry. Redaction happens at the dashboard boundary
(in addition to StreamManager's own redaction inside Godot), using
the exact secret values from this process's environment plus
patterns for ingest URLs carrying a key as the last path segment.
"""
import os
import re

SECRET_ENV_VARS = ("IWT_YOUTUBE_STREAM_KEY", "IWT_ADMIN_TOKEN",
                   "IWT_VIEWER_TOKEN")

_LIVE2_URL = re.compile(r"(rtmps?://[^\s\"']+/live2/)[^\s\"']+")
_KEY_FIELD = re.compile(r"((?:stream[_-]?key|admin[_-]?token|viewer[_-]?token)"
                        r"[\"']?\s*[=:]\\?\s*[\"']?)[^\s\"',}]+",
                        re.IGNORECASE)


def secret_values():
    values = []
    for name in SECRET_ENV_VARS:
        value = os.environ.get(name, "").strip()
        if len(value) >= 4:
            values.append(value)
    return values


def redact(text):
    if text is None:
        return text
    out = str(text)
    for value in secret_values():
        out = out.replace(value, "***")
    out = _LIVE2_URL.sub(r"\1***", out)
    out = _KEY_FIELD.sub(r"\1***", out)
    return out


def redact_obj(obj):
    """Recursively redact every string in a JSON-able structure."""
    if isinstance(obj, str):
        return redact(obj)
    if isinstance(obj, dict):
        return {key: redact_obj(value) for key, value in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [redact_obj(value) for value in obj]
    return obj
