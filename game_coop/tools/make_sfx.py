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


def clink():
    """Aluminum can hitting something: bright inharmonic ping, very short."""
    n = int(RATE * 0.25)
    partials = [(1850, 1.0, 22), (2730, 0.6, 30), (4100, 0.4, 40), (5900, 0.25, 55)]
    rng = random.Random(9)
    out = []
    for i in range(n):
        t = i / RATE
        s = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-t * d) for f, a, d in partials)
        s += rng.uniform(-1, 1) * math.exp(-t * 200) * 0.8  # tick of the impact
        out.append(s * min(t / 0.0005, 1.0))
    return out


def hitmarker():
    """Crisp little 'tick' for damage feedback."""
    n = int(RATE * 0.06)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 90)
        s = math.sin(2 * math.pi * 2600 * t) + 0.5 * math.sin(2 * math.pi * 4100 * t)
        out.append(s * env * min(t / 0.0003, 1.0))
    return out


def knock():
    """Three knuckle raps on a wooden door."""
    rng = random.Random(11)
    n = int(RATE * 0.6)
    out = [0.0] * n
    for k, start in enumerate([0.0, 0.17, 0.34]):
        noise = lowpass([rng.uniform(-1, 1) for _ in range(int(RATE * 0.12))], 1800)
        amp = 1.0 if k < 2 else 0.85
        for i in range(len(noise)):
            t = i / RATE
            body = math.sin(2 * math.pi * 170 * t) * 0.9 + math.sin(2 * math.pi * 410 * t) * 0.4
            s = (body * math.exp(-t * 45) + noise[i] * 2.5 * math.exp(-t * 120)) * amp
            j = int(start * RATE) + i
            if j < n:
                out[j] += s * min(t / 0.0005, 1.0)
    return out


def oven_hum():
    """Seamless 2s loop: mains hum (whole cycles, so the loop point is clean) plus fan rush."""
    rng = random.Random(13)
    dur, fade = 2.0, 0.15
    n, nf = int(RATE * dur), int(RATE * fade)
    noise = lowpass([rng.uniform(-1, 1) for _ in range(n + nf)], 700)
    # Crossfade the extra tail into the head so the noise loops without a click.
    for i in range(nf):
        a = i / nf
        noise[i] = noise[i] * a + noise[n + i] * (1 - a)
    out = []
    for i in range(n):
        t = i / RATE
        hum = math.sin(2 * math.pi * 60 * t) * 0.5 + math.sin(2 * math.pi * 120 * t) * 0.3 + math.sin(2 * math.pi * 180 * t) * 0.1
        out.append(hum * 0.6 + noise[i] * 2.0)
    return out


def fryer_sizzle():
    """Seamless 2s loop: bright oil hiss with random crackles and pops."""
    rng = random.Random(17)
    dur, fade = 2.0, 0.15
    n, nf = int(RATE * dur), int(RATE * fade)
    total = n + nf
    raw = [rng.uniform(-1, 1) for _ in range(total)]
    low = lowpass(raw, 2500)
    hiss = [r - l for r, l in zip(raw, low)]  # high-passed: the "shhh"
    out = [0.0] * total
    for i in range(total):
        wobble = 0.7 + 0.3 * math.sin(2 * math.pi * 3 * i / RATE + rng.uniform(-0.05, 0.05))
        out[i] = hiss[i] * 0.35 * wobble
    for _ in range(140):  # crackles
        start = rng.randrange(total)
        amp = rng.uniform(0.3, 1.0)
        for j in range(int(RATE * 0.006)):
            if start + j < total:
                out[start + j] += rng.uniform(-1, 1) * amp * math.exp(-j / (RATE * 0.0015))
    for i in range(nf):  # crossfade the tail into the head so the loop is seamless
        a = i / nf
        out[i] = out[i] * a + out[n + i] * (1 - a)
    return out[:n]


def kaching():
    """Cash register: drawer rattle into two bright bell hits."""
    rng = random.Random(19)
    n = int(RATE * 0.9)
    out = [0.0] * n
    rattle = lowpass([rng.uniform(-1, 1) for _ in range(int(RATE * 0.08))], 3000)
    for i, r in enumerate(rattle):
        out[i] += r * 1.5 * math.exp(-i / RATE * 30)
    for start, f0 in [(0.07, 2093.0), (0.16, 2637.0)]:  # C7 then E7
        for i in range(int(RATE * 0.7)):
            t = i / RATE
            s = sum(a * math.sin(2 * math.pi * f0 * r * t) * math.exp(-t * d)
                    for r, a, d in [(1.0, 1.0, 5.0), (2.0, 0.3, 8.0), (3.0, 0.15, 12.0)])
            j = int(start * RATE) + i
            if j < n:
                out[j] += s * 0.6 * min(t / 0.001, 1.0)
    return out


def terminal_beep():
    """Old computer chirp: two short square-wave beeps, the second higher."""
    n = int(RATE * 0.32)
    out = [0.0] * n
    for start, f in [(0.0, 880.0), (0.16, 1320.0)]:
        for i in range(int(RATE * 0.11)):
            t = i / RATE
            s = 1.0 if math.sin(2 * math.pi * f * t) >= 0 else -1.0
            j = int(start * RATE) + i
            out[j] += s * 0.5 * min(t / 0.002, 1.0) * min((0.11 - t) / 0.01, 1.0)
    return lowpass(out, 4000)


def bell():
    """Clock tower bell: one low, long, slightly sour bong."""
    n = int(RATE * 4.0)
    f0 = 196.0  # G3
    partials = [(0.5, 0.5, 0.6), (1.0, 1.0, 0.9), (1.19, 0.5, 1.3), (1.5, 0.35, 1.6), (2.0, 0.4, 1.9), (2.66, 0.2, 2.8)]
    out = []
    for i in range(n):
        t = i / RATE
        s = sum(a * math.sin(2 * math.pi * f0 * r * t) * math.exp(-t * d) for r, a, d in partials)
        out.append(s * min(t / 0.004, 1.0))
    return out


def punch_clock():
    """Time card stamp: a clack, then a heavy mechanical ka-CHUNK."""
    rng = random.Random(23)
    n = int(RATE * 0.45)
    out = [0.0] * n
    for start, f, amp in [(0.0, 900.0, 0.5), (0.14, 120.0, 1.0)]:
        noise = lowpass([rng.uniform(-1, 1) for _ in range(int(RATE * 0.2))], 2500)
        for i in range(len(noise)):
            t = i / RATE
            s = (math.sin(2 * math.pi * f * t) * 0.8 + noise[i] * 2.0) * math.exp(-t * 35) * amp
            j = int(start * RATE) + i
            if j < n:
                out[j] += s * min(t / 0.0005, 1.0)
    return out


def radio_static():
    """Radio clicking on: a burst of band-passed static that settles down."""
    rng = random.Random(29)
    n = int(RATE * 0.7)
    raw = [rng.uniform(-1, 1) for _ in range(n)]
    band = [h - l for h, l in zip(lowpass(raw, 3500), lowpass(raw, 600))]
    out = []
    for i in range(n):
        t = i / RATE
        crackle = 1.0 + (3.0 if rng.random() < 0.002 else 0.0)
        out.append(band[i] * crackle * min(t / 0.01, 1.0) * (0.35 + 0.65 * math.exp(-t * 4)))
    return out


def neon_buzz():
    """Neon sign flickering on: stuttering mains buzz."""
    n = int(RATE * 0.9)
    out = []
    for i in range(n):
        t = i / RATE
        on = 1.0 if (t > 0.6 or int(t * 14) % 3 != 1) else 0.15
        s = 1.0 if math.sin(2 * math.pi * 120 * t) > 0.6 else -0.3
        out.append(s * on * 0.4)
    return lowpass(out, 1800)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for k in range(4):
        write("footstep_%d.wav" % (k + 1), footstep(k + 7))
    write("pickup.wav", pickup())
    write("ding.wav", ding())
    write("whoosh.wav", whoosh())
    write("thud.wav", thud())
    write("clink.wav", clink())
    write("hitmarker.wav", hitmarker())
    write("knock.wav", knock())
    write("oven_hum.wav", oven_hum())
    write("fryer_sizzle.wav", fryer_sizzle())
    write("kaching.wav", kaching())
    write("terminal_beep.wav", terminal_beep())
    write("bell.wav", bell())
    write("punch_clock.wav", punch_clock())
    write("radio_static.wav", radio_static())
    write("neon_buzz.wav", neon_buzz())
