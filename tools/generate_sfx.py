#!/usr/bin/env python3
"""
generate_sfx.py — synthesize all placeholder SFX for Awakening Brochacho.

Outputs .wav files directly into assets/audio/sfx/.
Godot imports .wav natively — no conversion needed.

Run from the project root:
    python3 tools/generate_sfx.py
"""

import wave
import struct
import math
import random
import os

SAMPLE_RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")

# ---------------------------------------------------------------------------
# Core synthesis primitives
# ---------------------------------------------------------------------------

def _write_wav(path: str, samples: list[float]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        for s in samples:
            clamped = max(-1.0, min(1.0, s))
            f.writeframes(struct.pack("<h", int(clamped * 32767)))
    print(f"  wrote {os.path.basename(path)}")


def _sine(freq: float, dur: float, amp: float = 1.0) -> list[float]:
    n = int(dur * SAMPLE_RATE)
    return [amp * math.sin(2 * math.pi * freq * i / SAMPLE_RATE) for i in range(n)]


def _square(freq: float, dur: float, amp: float = 0.4) -> list[float]:
    n = int(dur * SAMPLE_RATE)
    return [amp * (1.0 if math.sin(2 * math.pi * freq * i / SAMPLE_RATE) >= 0 else -1.0)
            for i in range(n)]


def _noise(dur: float, amp: float = 1.0) -> list[float]:
    n = int(dur * SAMPLE_RATE)
    return [amp * (random.random() * 2 - 1) for _ in range(n)]


def _sweep(f0: float, f1: float, dur: float, amp: float = 1.0) -> list[float]:
    """Linear frequency sweep (chirp)."""
    n = int(dur * SAMPLE_RATE)
    result = []
    for i in range(n):
        t = i / SAMPLE_RATE
        # Instantaneous frequency varies linearly; phase is integral of freq.
        phase = 2 * math.pi * (f0 * t + 0.5 * (f1 - f0) * t * t / dur)
        result.append(amp * math.sin(phase))
    return result


def _env(samples: list[float],
         attack: float = 0.01, decay: float = 0.05,
         sustain: float = 0.8, release: float = 0.1) -> list[float]:
    """Apply an ADSR amplitude envelope."""
    n = len(samples)
    sr = SAMPLE_RATE
    a, d, r = int(attack * sr), int(decay * sr), int(release * sr)
    s_len = max(0, n - a - d - r)

    env: list[float] = []
    for i in range(min(a, n)):
        env.append(i / max(a, 1))
    for i in range(min(d, n - len(env))):
        env.append(1.0 - (1.0 - sustain) * i / max(d, 1))
    for i in range(min(s_len, n - len(env))):
        env.append(sustain)
    while len(env) < n:
        i = len(env) - (a + d + s_len)
        env.append(max(0.0, sustain * (1.0 - i / max(r, 1))))

    return [samples[i] * env[i] for i in range(n)]


def _mix(*tracks: list[float]) -> list[float]:
    n = max(len(t) for t in tracks)
    result = [0.0] * n
    for track in tracks:
        for i, s in enumerate(track):
            result[i] += s
    peak = max((abs(s) for s in result), default=1.0)
    if peak > 0.9:
        result = [s / peak * 0.9 for s in result]
    return result


def _concat(*tracks: list[float]) -> list[float]:
    result: list[float] = []
    for t in tracks:
        result.extend(t)
    return result


def _fade_out(samples: list[float], fade_dur: float = 0.05) -> list[float]:
    n = len(samples)
    fade_n = min(int(fade_dur * SAMPLE_RATE), n)
    out = list(samples)
    for i in range(fade_n):
        out[n - fade_n + i] *= 1.0 - i / fade_n
    return out


def _lowpass(samples: list[float], cutoff_hz: float) -> list[float]:
    """Simple single-pole IIR lowpass filter."""
    rc = 1.0 / (2 * math.pi * cutoff_hz)
    dt = 1.0 / SAMPLE_RATE
    alpha = dt / (rc + dt)
    out = list(samples)
    for i in range(1, len(out)):
        out[i] = out[i - 1] + alpha * (samples[i] - out[i - 1])
    return out


def _save(name: str, samples: list[float]) -> None:
    _write_wav(os.path.join(OUT_DIR, name + ".wav"), _fade_out(samples))


# ---------------------------------------------------------------------------
# Sound definitions
# ---------------------------------------------------------------------------

def footstep_grass() -> list[float]:
    body = _lowpass(_noise(0.06, 0.7), 800)
    return _env(body, attack=0.002, decay=0.04, sustain=0.0, release=0.02)


def footstep_stone() -> list[float]:
    click = _env(_noise(0.04, 0.9), attack=0.001, decay=0.02, sustain=0.0, release=0.02)
    tone  = _env(_sine(180, 0.04, 0.3), attack=0.001, decay=0.03, sustain=0.0, release=0.01)
    return _mix(click, tone)


def footstep_wood() -> list[float]:
    body = _lowpass(_noise(0.06, 0.6), 1200)
    tone = _env(_sine(220, 0.06, 0.2), attack=0.002, decay=0.04, sustain=0.0, release=0.02)
    return _mix(_env(body, attack=0.002, decay=0.04, sustain=0.0, release=0.02), tone)


def interact() -> list[float]:
    # Two-tone ascending chime
    a = _env(_sine(660, 0.12, 0.8), attack=0.002, decay=0.05, sustain=0.3, release=0.08)
    b = _env(_sine(880, 0.12, 0.6), attack=0.01, decay=0.05, sustain=0.3, release=0.08)
    silence = [0.0] * int(0.05 * SAMPLE_RATE)
    return _concat(a, silence, b)


def chest_open() -> list[float]:
    creak = _env(_lowpass(_noise(0.2, 0.5), 600), attack=0.01, decay=0.1, sustain=0.3, release=0.1)
    jingle = _env(_sine(1320, 0.15, 0.7), attack=0.002, decay=0.06, sustain=0.1, release=0.1)
    jingle2 = _env(_sine(1760, 0.12, 0.5), attack=0.002, decay=0.05, sustain=0.1, release=0.08)
    silence = [0.0] * int(0.18 * SAMPLE_RATE)
    return _mix(creak, _concat(silence, jingle, [0.0] * int(0.04 * SAMPLE_RATE), jingle2))


def door_open() -> list[float]:
    sweep = _sweep(300, 80, 0.35, 0.6)
    noise_layer = _lowpass(_noise(0.35, 0.3), 500)
    combined = _mix(sweep, noise_layer)
    return _env(combined, attack=0.02, decay=0.1, sustain=0.5, release=0.15)


def dialogue_open() -> list[float]:
    return _env(_sweep(200, 600, 0.25, 0.7), attack=0.01, decay=0.05, sustain=0.6, release=0.12)


def dialogue_next() -> list[float]:
    click = _env(_sine(1000, 0.08, 0.6), attack=0.001, decay=0.03, sustain=0.0, release=0.05)
    tick  = _env(_noise(0.02, 0.2), attack=0.001, decay=0.015, sustain=0.0, release=0.005)
    return _mix(click, tick)


def dialogue_close() -> list[float]:
    return _env(_sweep(600, 200, 0.22, 0.7), attack=0.005, decay=0.05, sustain=0.5, release=0.15)


def item_pickup() -> list[float]:
    # Short ascending arpeggio: C E G
    c = _env(_sine(523, 0.1, 0.7), attack=0.002, decay=0.04, sustain=0.2, release=0.06)
    e = _env(_sine(659, 0.1, 0.6), attack=0.002, decay=0.04, sustain=0.2, release=0.06)
    g = _env(_sine(784, 0.15, 0.8), attack=0.002, decay=0.05, sustain=0.3, release=0.1)
    gap = [0.0] * int(0.07 * SAMPLE_RATE)
    return _concat(c, gap, e, gap, g)


def item_equip() -> list[float]:
    ting = _env(_sine(1047, 0.2, 0.7), attack=0.001, decay=0.08, sustain=0.2, release=0.12)
    metal = _env(_noise(0.04, 0.3), attack=0.001, decay=0.03, sustain=0.0, release=0.01)
    return _mix(ting, metal)


def gold_pickup() -> list[float]:
    freqs = [1047, 1319, 1047, 1568]
    result: list[float] = []
    for f in freqs:
        result.extend(_env(_sine(f, 0.07, 0.6), attack=0.001, decay=0.04, sustain=0.1, release=0.03))
        result.extend([0.0] * int(0.015 * SAMPLE_RATE))
    return result


def quest_start() -> list[float]:
    # Rising two-note motif — "something begins"
    low  = _env(_sine(392, 0.18, 0.7), attack=0.01, decay=0.05, sustain=0.5, release=0.1)
    high = _env(_sine(523, 0.25, 0.8), attack=0.01, decay=0.06, sustain=0.5, release=0.15)
    gap  = [0.0] * int(0.1 * SAMPLE_RATE)
    return _concat(low, gap, high)


def quest_complete() -> list[float]:
    # Four-note resolution: G A B C — triumphant close
    notes = [(392, 0.12), (440, 0.12), (494, 0.12), (523, 0.30)]
    result: list[float] = []
    for freq, dur in notes:
        result.extend(_env(_sine(freq, dur, 0.8), attack=0.005, decay=0.04, sustain=0.5, release=0.08))
        result.extend([0.0] * int(0.04 * SAMPLE_RATE))
    return result


def menu_open() -> list[float]:
    sweep = _sweep(400, 800, 0.2, 0.5)
    soft  = _lowpass(_noise(0.2, 0.15), 1000)
    return _env(_mix(sweep, soft), attack=0.02, decay=0.05, sustain=0.6, release=0.1)


def menu_close() -> list[float]:
    sweep = _sweep(800, 400, 0.18, 0.5)
    soft  = _lowpass(_noise(0.18, 0.15), 1000)
    return _env(_mix(sweep, soft), attack=0.005, decay=0.05, sustain=0.5, release=0.1)


def button_confirm() -> list[float]:
    return _env(_sine(880, 0.08, 0.7), attack=0.001, decay=0.03, sustain=0.2, release=0.05)


def button_cancel() -> list[float]:
    return _env(_sine(440, 0.08, 0.6), attack=0.001, decay=0.03, sustain=0.2, release=0.05)


def era_transition() -> list[float]:
    # Shimmering ascending sweep with harmonic shimmer
    base    = _sweep(200, 3000, 1.0, 0.6)
    shimmer = _sweep(400, 6000, 1.0, 0.3)
    shimmer2 = _sweep(600, 9000, 0.9, 0.15)
    combined = _mix(base, shimmer, shimmer2)
    return _env(combined, attack=0.05, decay=0.2, sustain=0.6, release=0.4)


def sword_swing() -> list[float]:
    sweep = _sweep(800, 200, 0.18, 0.7)
    hiss  = _lowpass(_noise(0.18, 0.4), 3000)
    return _env(_mix(sweep, hiss), attack=0.002, decay=0.06, sustain=0.3, release=0.1)


def hit_impact() -> list[float]:
    thud  = _env(_sine(80, 0.15, 0.8), attack=0.001, decay=0.05, sustain=0.1, release=0.1)
    crack = _env(_lowpass(_noise(0.08, 0.6), 2000), attack=0.001, decay=0.04, sustain=0.0, release=0.04)
    return _mix(thud, crack)


def player_hurt() -> list[float]:
    sting  = _env(_sine(330, 0.1, 0.7), attack=0.001, decay=0.03, sustain=0.1, release=0.07)
    noise_ = _env(_lowpass(_noise(0.15, 0.5), 1500), attack=0.001, decay=0.05, sustain=0.2, release=0.1)
    sweep  = _sweep(500, 200, 0.2, 0.4)
    return _mix(sting, noise_, _env(sweep, attack=0.01, decay=0.05, sustain=0.3, release=0.1))


def enemy_death() -> list[float]:
    descend = _sweep(600, 100, 0.35, 0.6)
    gravel  = _lowpass(_noise(0.35, 0.4), 1200)
    return _env(_mix(descend, gravel), attack=0.005, decay=0.1, sustain=0.4, release=0.2)


def dungeon_descend() -> list[float]:
    rumble  = _lowpass(_noise(0.6, 0.7), 300)
    low_sweep = _sweep(120, 40, 0.6, 0.5)
    return _env(_mix(rumble, low_sweep), attack=0.05, decay=0.15, sustain=0.5, release=0.3)


# ---------------------------------------------------------------------------
# Generate all sounds
# ---------------------------------------------------------------------------

SOUNDS: dict[str, callable] = {
    "footstep_grass"  : footstep_grass,
    "footstep_stone"  : footstep_stone,
    "footstep_wood"   : footstep_wood,
    "interact"        : interact,
    "chest_open"      : chest_open,
    "door_open"       : door_open,
    "dialogue_open"   : dialogue_open,
    "dialogue_next"   : dialogue_next,
    "dialogue_close"  : dialogue_close,
    "item_pickup"     : item_pickup,
    "item_equip"      : item_equip,
    "gold_pickup"     : gold_pickup,
    "quest_start"     : quest_start,
    "quest_complete"  : quest_complete,
    "menu_open"       : menu_open,
    "menu_close"      : menu_close,
    "button_confirm"  : button_confirm,
    "button_cancel"   : button_cancel,
    "era_transition"  : era_transition,
    "sword_swing"     : sword_swing,
    "hit_impact"      : hit_impact,
    "player_hurt"     : player_hurt,
    "enemy_death"     : enemy_death,
    "dungeon_descend" : dungeon_descend,
}


def main() -> None:
    print(f"Generating {len(SOUNDS)} SFX into {os.path.abspath(OUT_DIR)}/")
    for name, fn in SOUNDS.items():
        samples = fn()
        _save(name, samples)
    print(f"\nDone — {len(SOUNDS)} .wav files written.")
    print("Godot will auto-import them on next editor open.")
    print("\nNote: AudioManager expects .ogg but also accepts .wav.")
    print("Update AudioManager SFX dict extensions from .ogg to .wav, or")
    print("convert with: for f in assets/audio/sfx/*.wav; do ffmpeg -i $f ${f%.wav}.ogg; done")


if __name__ == "__main__":
    main()
