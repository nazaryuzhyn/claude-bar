#!/usr/bin/env python3
"""Synthesize ClaudeBar's two notification sounds from oscillators, without samples.

Adapted from Lunavect's scripts/generate-notification-sound.py,
Copyright (c) 2026 Lunavect contributors, MIT License (see THIRD_PARTY_NOTICES).

done.wav    two soft rising notes, lower and warmer than Lunavect's Lift
waiting.wav two short equal knocks: told apart from done by rhythm, not only pitch
"""
from pathlib import Path
import json
import math
import struct
import wave

RATE = 48000
TAU = 2 * math.pi
OUTPUT = Path(__file__).resolve().parents[1] / 'Resources' / 'Sounds'


def voice(t, pitch, amplitude, decay, warmth=.12, glass=.09):
    if t <= 0:
        return 0.0
    attack = math.sin(min(1.0, t / .006) * math.pi / 2) ** 2
    fundamental = math.sin(TAU * pitch * t) * math.exp(-t / decay)
    body = warmth * math.sin(TAU * pitch * 2 * t + .18) * math.exp(-t / .025)
    ring = glass * math.sin(TAU * pitch * 2.71 * t + .32) * math.exp(-t / .031)
    return amplitude * attack * (fundamental + body + ring)


def done(t):
    # C5 then E5: a calm major third.
    return voice(t, 523.251, .82, .085, warmth=.2, glass=.04) + voice(t - .085, 659.255, .7, .1, warmth=.2, glass=.04)


def waiting(t):
    # Two equal A5 knocks 140 ms apart.
    return voice(t, 880.0, .8, .03, warmth=.08, glass=.12) + voice(t - .14, 880.0, .8, .03, warmth=.08, glass=.12)


def render(name, dry, duration):
    frames = []
    for i in range(round(RATE * duration)):
        t = i / RATE
        fade = math.sin(min(1.0, (duration - t) / .045) * math.pi / 2) ** 2
        # Very small reflections lend space without a long reverb tail.
        left = (dry(t) + .052 * dry(t - .017) + .024 * dry(t - .041)) * fade
        right = (dry(t) + .052 * dry(t - .022) + .024 * dry(t - .047)) * fade
        frames.append((left, right))

    active = frames[:round(.3 * RATE)]
    rms = math.sqrt(sum(l * l + r * r for l, r in active) / (len(active) * 2))
    peak = max(abs(v) for pair in frames for v in pair)
    scale = min(10 ** (-23 / 20) / rms, .40 / peak)
    frames = [(l * scale, r * scale) for l, r in frames]
    assert max(abs(v) for pair in frames for v in pair) <= .40001
    assert all(abs(v) < .00001 for v in frames[0] + frames[-1])

    OUTPUT.mkdir(parents=True, exist_ok=True)
    path = OUTPUT / f'{name}.wav'
    with wave.open(str(path), 'wb') as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b''.join(struct.pack('<hh', round(l * 32767), round(r * 32767)) for l, r in frames))
    return {
        'file': str(path),
        'seconds': duration,
        'peak_dbfs': round(20 * math.log10(peak * scale), 2),
        'first_300ms_rms_dbfs': round(20 * math.log10(rms * scale), 2),
    }


print(json.dumps([render('done', done, .45), render('waiting', waiting, .4)], indent=2))
