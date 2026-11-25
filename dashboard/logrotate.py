"""Phase 09 — bounded append-only logs for the dashboard layer.

Before Phase 09 every JSONL/process log in the dashboard runtime
dir (dashboard_log.jsonl, audit.jsonl, alerts.jsonl,
game_process.log, stream_process.log) was append-only forever:
on a weeks-long run they grow without bound and eventually fill
the disk the recordings live on — the exact failure Phase 06's
StorageManager prevents for video but nothing prevented for logs.

rotate_if_needed(path) keeps at most `backups` rotated siblings
(path.1 … path.N); when the live file passes max_bytes it is
shifted once, before the next append. Rotation is best-effort:
a failure to rotate must never take the writer down, so all
filesystem errors are swallowed and the append still happens.
"""
import os

DEFAULT_MAX_BYTES = 5 * 1024 * 1024
DEFAULT_BACKUPS = 3


def rotate_if_needed(path, max_bytes=DEFAULT_MAX_BYTES,
                     backups=DEFAULT_BACKUPS):
    """Shift path -> path.1 -> … -> path.<backups> if oversized.

    Returns True when a rotation happened. Never raises.
    """
    try:
        if os.path.getsize(path) < max_bytes:
            return False
    except OSError:
        return False
    try:
        oldest = "%s.%d" % (path, backups)
        if os.path.exists(oldest):
            os.remove(oldest)
        for index in range(backups - 1, 0, -1):
            src = "%s.%d" % (path, index)
            if os.path.exists(src):
                os.replace(src, "%s.%d" % (path, index + 1))
        os.replace(path, "%s.1" % path)
        return True
    except OSError:
        return False


def append_line(path, line, max_bytes=DEFAULT_MAX_BYTES,
                backups=DEFAULT_BACKUPS):
    """Rotate if needed, then append one line. Never raises."""
    rotate_if_needed(path, max_bytes, backups)
    try:
        with open(path, "a") as handle:
            handle.write(line)
        return True
    except OSError:
        return False


def total_size(path, backups=DEFAULT_BACKUPS):
    """Live file + rotated siblings, in bytes (for reporting)."""
    total = 0
    for candidate in [path] + ["%s.%d" % (path, i)
                               for i in range(1, backups + 1)]:
        try:
            total += os.path.getsize(candidate)
        except OSError:
            pass
    return total
