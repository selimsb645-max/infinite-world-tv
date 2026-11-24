# Infrastructure — where this can actually run 24/7

The specification is explicit: do not treat GitHub Actions as a permanent server. This
document says what that leaves, with real numbers.

## 1. What each part needs

| Part | Uptime needed | CPU | GPU | Disk | Network |
|---|---|---|---|---|---|
| Level generation + tests | none (bursty) | 1 core | no | small | none |
| Godot Movie Maker render | none (bursty) | 2-4 cores | no (software) | ~2 GB/hour of frames | none |
| FFmpeg encode | none (bursty) | 1-2 cores | optional (NVENC) | ~0.3 GB/hour at 4.5 Mbps | none |
| **Stream loop** | **24/7** | **< 1 core** | **no** | ~30 GB buffer | **~48 GB/day up** |
| Dashboard | 24/7 (light) | < 0.5 core | no | small | small |

Only the last two need to be always on. That is the whole point of the render-ahead design.

## 2. Options, honestly compared

### A. Oracle Cloud Always Free (recommended for zero cost)
- 4 ARM cores / 24 GB RAM, always free, no time limit.
- Egress: 10 TB/month free — 48 GB/day ≈ 1.4 TB/month, comfortably inside.
- Reality: signup approval can take days and cards get declined; ARM capacity in some regions
  is full; the account can be reclaimed if idle (streaming keeps it busy, which helps).
- Verdict: best zero-cost fit **if** the account gets approved.

### B. The owner's own PC
- Zero marginal cost, GPU available, so rendering is fast.
- Requires the PC to be on ~24/7 and a stable connection; a power cut ends the stream.
- Good as the **render** host even if the stream runs elsewhere.

### C. Cheap VPS (~$5/month)
- Reliable, predictable, root access, no approval friction.
- Not zero cost. Needs approval per the spec's rule on paid dependencies.

### D. GitHub Actions — render farm only
- Free minutes, 2-4 cores, no GPU, no persistent process.
- Perfect for: unit tests, level-uniqueness soak tests, batch rendering of segments, and
  committing them as release artifacts.
- Cannot: stream, hold a process, or act as the dashboard.

### Rejected outright
- **YouTube Live from a laptop with sleep enabled** — the stream dies silently.
- **Any "free VPS" without an SLA** — these are the accounts that vanish mid-month.
- **Cloud Run / Lambda style services** — they cannot hold an RTMP connection open.

## 3. Recommended topology (zero cost)

```
Owner PC (or Oracle ARM)          GitHub Actions              Oracle ARM (always on)
  Godot render ─► segments ─────► artifacts ────────────────► stream_loop.py ─► YouTube
  (bursty, fast)                  (tests + soak)               dashboard (FastAPI)
```

If only one always-on box exists, it does both: render when the buffer is short, stream
otherwise. The buffer check makes the two jobs coexist without a scheduler.

## 4. Egress and platform rules that bite

- **YouTube**: new channels need up to 24h to enable live streaming; a 24/7 stream counts as
  one long stream, so an accidental disconnect ends the "video" and a new one starts (viewers
  drop). Reconnect logic matters more than bitrate.
- **YouTube content rules**: a 24/7 automated stream must still comply — original audio (ours
  is synthesised), no misleading metadata, and the correct "made for kids" audience setting.
- **Egress caps**: a 10 TB/month cap is the practical minimum; 4.5 Mbps at 1080p60 is the
  sweet spot. 1080p30 at 3 Mbps halves the risk.
- **Disk**: keep a 30-60 minute buffer (~1-2 GB), not a day of segments.

## 5. What must be measured before launch

1. Render throughput: minutes of video per hour of CPU, on the chosen host.
2. Stream stability over 24h: reconnects, dropped frames, bitrate variance.
3. Memory: a 6-hour soak with the generator running continuously (leak check).
4. Egress: actual GB/day measured, not estimated.

No claim of "unlimited" or "24/7 guaranteed" is allowed until (2) and (4) are measured and
written into this document.
