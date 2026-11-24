#!/usr/bin/env python3
"""Phase 05 — synthesise the original audio library as 16-bit WAVs.

All clips are original synthesis (sine/triangle/noise envelopes) — no
external or licensed audio. Run from the repo root:

    python3 tools/generate_audio.py

Writes into game/assets/audio/. Keep clips short and loop clips
periodic (integer cycles) so Godot's LOOP_FORWARD is seamless.
"""
import math
import os
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "game", "assets", "audio")


def _write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    frames = b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767))))
                      for s in samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    print(f"{name}: {len(samples) / SR:.2f}s")


def _sine(freq, dur, amp=0.5, fade_out=True):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        env = 1.0 - (i / n) if fade_out else 1.0
        out.append(amp * math.sin(2 * math.pi * freq * t) * env)
    return out


def _sweep(f0, f1, dur, amp=0.5):
    n = int(SR * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / SR
        freq = f0 + (f1 - f0) * (i / n)
        phase += 2 * math.pi * freq / SR
        env = 1.0 - (i / n) ** 2
        out.append(amp * math.sin(phase) * env)
    return out


def _tone_seq(notes, note_dur, amp=0.45):
    out = []
    for freq in notes:
        out.extend(_sine(freq, note_dur, amp))
    return out


def _noise(dur, amp=0.3, lowpass=0.2):
    import random
    random.seed(7)
    n = int(SR * dur)
    out, last = [], 0.0
    for i in range(n):
        raw = random.uniform(-1, 1)
        last = last + lowpass * (raw - last)
        env = 1.0 - (i / n)
        out.append(amp * last * env)
    return out


def _mix(a, b):
    n = max(len(a), len(b))
    a = a + [0.0] * (n - len(a))
    b = b + [0.0] * (n - len(b))
    return [x + y for x, y in zip(a, b)]


def _loop_pad(freqs, dur, amp=0.25):
    """Pad with integer cycles per frequency so the loop is seamless."""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        s = sum(math.sin(2 * math.pi * f * t) for f in freqs) / len(freqs)
        # gentle 50ms edge fade so the loop point never clicks
        edge = min(1.0, i / (SR * 0.05), (n - i) / (SR * 0.05))
        out.append(amp * s * edge)
    return out


def main():
    _write("jump.wav", _sweep(300, 720, 0.35))
    _write("land.wav", _mix(_sine(120, 0.18, 0.6), _noise(0.12, 0.2)))
    _write("collect.wav", _tone_seq([880, 1318], 0.15))
    _write("coin.wav", _tone_seq([988, 1319], 0.12))
    _write("star.wav", _tone_seq([784, 988, 1175, 1568], 0.12))
    _write("energy.wav", _sweep(500, 1200, 0.4, 0.4))
    _write("ui_click.wav", _sine(1250, 0.08, 0.35))
    _write("run.wav", _mix(_noise(0.1, 0.25), _sine(180, 0.1, 0.15)))
    _write("transition.wav", _sweep(200, 1800, 0.5, 0.35))
    _write("celebrate.wav", _tone_seq([523, 659, 784, 1047], 0.2))
    # Engine: periodic 55 Hz + harmonics, exactly 55 cycles per second.
    n = SR
    _write("engine.wav", [
        0.3 * math.sin(2 * math.pi * 55 * i / SR)
        + 0.15 * math.sin(2 * math.pi * 110 * i / SR)
        + 0.06 * math.sin(2 * math.pi * 165 * i / SR)
        for i in range(n)])
    # Music: 8 s, C-major pentatonic pad, integer cycles (4 bars x 2 s).
    _write("music.wav", _loop_pad([261.63, 329.63, 392.0, 523.25], 8.0, 0.22))
    ambience = {
        "ambience_green_valley": [440.0, 660.0, 880.0],
        "ambience_neon_city": [110.0, 220.0, 330.0],
        "ambience_desert_world": [196.0, 294.0, 392.0],
        "ambience_snow_mountain": [523.25, 784.0, 1046.5],
        "ambience_space_world": [130.81, 196.0, 261.63],
        "ambience_ocean_world": [174.61, 261.63, 349.23],
        "ambience_fantasy_islands": [392.0, 523.25, 659.25],
        "ambience_futuristic_highway": [146.83, 293.66, 440.0],
    }
    for name, freqs in ambience.items():
        _write(f"{name}.wav", _loop_pad(freqs, 4.0, 0.16))
    print("done.")


if __name__ == "__main__":
    main()
