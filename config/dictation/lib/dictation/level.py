"""Noise-floor-aware input level: one value 0..1 per 32 ms frame for the pill, plus a voiced flag for the engine.

    meter = LevelMeter()
    value, voiced = meter.push(rms)      # rms of one frame (linear, full scale 1.0)

Everything is relative to the session's own noise floor, so the result does not depend on the mic gain:

1. x = frame level in dB (RMS, floored at -100 dB; frames under -90 dB are digital zeros and leave the floor alone). For the floor a lightly smoothed copy (power average, ~70 ms) is
   used, so a single quiet frame inside a word does not pull it down.
2. Noise floor: a running minimum of the smoothed level that follows drops at once and rises slowly
   (`floor_rise` dB/s; only `floor_rise_voiced` while the frame is voiced, so fluent speech never lifts it), so it
   sits on the room noise / mic hiss between words and adapts to a fan turned on.
3. Gate: what is less than `gate` dB above the floor is silence: exactly 0.
4. Reference: a running peak of x that decays slowly (`peak_decay` dB/s), never closer to the floor than `min_span`
   dB above the gate (so hiss alone is never stretched to full scale and a quiet mic still reaches the top).
5. Curve: t = (x - floor - gate) / span in 0..1, value = smoothstep over t in `knee` (0.1..1.0): soft sounds
   (breath, a click: low t) stay small, normal speech lands at ~0.6-1.0
   (measured on recorded speech with noise added: median 0.90 clean, 0.73-0.75 at 20 dB SNR).
6. Smoothing: fast attack, moderate release (per-frame factors `attack` / `release`), snapped to 0 below 0.01 so
   silence is a true 0.

voiced: x at least `voice` dB above the floor (and not gated): the engine's end-of-speech detector uses it.
"""
from __future__ import annotations

import math

FRAME_S = 512 / 16000  # one level frame (32 ms)
DIGITAL_SILENCE = -90.0  # dB; quieter frames are digital zeros, not room noise, and never move the floor


class LevelMeter:
    def __init__(self, *, gate: float = 6.0, voice: float = 8.0, min_span: float = 14.0, floor_rise: float = 1.5,
                 floor_rise_voiced: float = 0.3, peak_decay: float = 1.5, knee: tuple = (0.1, 1.0), attack: float = 0.7, release: float = 0.22,
                 frame_s: float = FRAME_S):
        self.gate, self.voice, self.min_span = gate, voice, min_span
        self.floor_rise, self.peak_decay = floor_rise * frame_s, peak_decay * frame_s
        self.floor_rise_voiced = floor_rise_voiced * frame_s
        self.attack, self.release, self.knee = attack, release, knee
        self.floor: float | None = None  # dB
        self.peak = -100.0
        self._power = None  # smoothed power for the floor
        self.value = 0.0

    def push(self, rms: float) -> tuple:
        power = max(rms, 1e-5) ** 2
        x = 10 * math.log10(power)
        if x < DIGITAL_SILENCE:
            xs = None  # exact zeros (a muted source, a file that ended) say nothing about the room: the floor stays
        else:
            self._power = power if self._power is None else 0.6 * self._power + 0.4 * power
            xs = 10 * math.log10(self._power)
        if xs is None:
            pass
        elif self.floor is None or xs < self.floor:
            self.floor = xs
        else:
            # while voiced the floor barely moves: the gaps between words never reach the room noise, and a floor
            # creeping up under fluent speech would end the "voiced" speech after a few seconds
            rise = self.floor_rise_voiced if x - self.floor >= self.voice else self.floor_rise
            self.floor = min(xs, self.floor + rise)
        if self.floor is None:
            self.value = 0.0
            return 0.0, False
        self.peak = max(x, self.peak - self.peak_decay)
        over = x - self.floor - self.gate
        span = max(self.peak - self.floor - self.gate, self.min_span)
        t = min(1.0, max(0.0, over / span))
        e = min(1.0, max(0.0, (t - self.knee[0]) / (self.knee[1] - self.knee[0])))
        target = e * e * (3 - 2 * e)  # smoothstep: soft sounds stay small, speech climbs fast to the top
        k = self.attack if target > self.value else self.release
        self.value += (target - self.value) * k
        if self.value < 0.01:
            self.value = 0.0
        return self.value, x - self.floor >= self.voice
