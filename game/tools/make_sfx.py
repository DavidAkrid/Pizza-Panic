"""Generates placeholder sound effects into ../audio/. Run: python make_sfx.py

Replace any .wav in audio/ with a real sound later; keep the filename.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


def write(name, samples):
    peak = max(abs(s) for s in samples) or 1.0
    frames = b"".join(struct.pack("<h", int(s / peak * 0.9 * 32767)) for s in samples)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print("wrote", name)


def lowpass(samples, cutoff):
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    y, out = 0.0, []
    for x in samples:
        y += a * (x - y)
        out.append(y)
    return out


def footstep(seed):
    """Soft scuff: low-passed noise burst plus a little low thump."""
    rng = random.Random(seed)
    n = int(RATE * 0.14)
    noise = lowpass([rng.uniform(-1, 1) for _ in range(n)], rng.uniform(500, 900))
    thump_f = rng.uniform(65, 95)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(t / 0.003, 1.0) * math.exp(-t * 38)
        thump = math.sin(2 * math.pi * thump_f * t) * math.exp(-t * 55) * 0.6
        out.append(noise[i] * 3.0 * env + thump)
    return out


def pickup():
    """Short upward 'bloop'."""
    n = int(RATE * 0.13)
    phase, out = 0.0, []
    for i in range(n):
        t = i / RATE
        f = 480 * (2.3 ** (t / 0.13))
        phase += 2 * math.pi * f / RATE
        env = min(t / 0.002, 1.0) * math.exp(-t * 28)
        out.append((math.sin(phase) + 0.2 * math.sin(2 * phase)) * env)
    return out


def ding():
    """Kitchen-timer bell."""
    n = int(RATE * 1.8)
    f0 = 1318.5  # E6
    partials = [(1.0, 1.0, 2.6), (2.0, 0.35, 4.0), (2.76, 0.25, 5.5), (5.4, 0.1, 9.0)]
    out = []
    for i in range(n):
        t = i / RATE
        attack = min(t / 0.002, 1.0)
        s = sum(a * math.sin(2 * math.pi * f0 * r * t) * math.exp(-t * d) for r, a, d in partials)
        out.append(s * attack)
    return out


def whoosh():
    """Air swish: noise through a lowpass that sweeps up then down."""
    rng = random.Random(3)
    dur = 0.2
    n = int(RATE * dur)
    y, out = 0.0, []
    for i in range(n):
        t = i / RATE
        shape = math.sin(math.pi * t / dur)
        a = 1.0 - math.exp(-2.0 * math.pi * (300 + 2500 * shape) / RATE)
        y += a * (rng.uniform(-1, 1) - y)
        out.append(y * shape * shape)
    return out


def thud():
    """Meaty impact: falling-pitch thump plus a short crunch."""
    rng = random.Random(5)
    n = int(RATE * 0.22)
    noise = lowpass([rng.uniform(-1, 1) for _ in range(n)], 1500)
    phase, out = 0.0, []
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (60 + 70 * math.exp(-t * 30)) / RATE
        body = math.sin(phase) * math.exp(-t * 18)
        crunch = noise[i] * 2.5 * math.exp(-t * 45)
        out.append((body + crunch) * min(t / 0.001, 1.0))
    return out


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for k in range(4):
        write("footstep_%d.wav" % (k + 1), footstep(k + 7))
    write("pickup.wav", pickup())
    write("ding.wav", ding())
    write("whoosh.wav", whoosh())
    write("thud.wav", thud())
