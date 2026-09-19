"""Procedurally generates all game sounds as 16-bit mono WAV files.
Run:  python3 tools/gen_audio.py audio
"""
import os, sys, math, random, struct, wave

OUT = sys.argv[1] if len(sys.argv) > 1 else "audio"
os.makedirs(OUT, exist_ok=True)
SR = 22050
random.seed(7)


def write_wav(name, samples):
    path = os.path.join(OUT, name)
    frames = bytearray()
    for s in samples:
        v = max(-1.0, min(1.0, s))
        frames += struct.pack("<h", int(v * 32000))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    return path, len(samples) / float(SR)


def n(count):
    return [random.uniform(-1, 1) for _ in range(count)]


def lowpass(sig, a):
    out, prev = [], 0.0
    for s in sig:
        prev = prev + a * (s - prev)
        out.append(prev)
    return out


def highpass(sig, a):
    return [s - l for s, l in zip(sig, lowpass(sig, a))]


def env_exp(length, decay, attack=0.002):
    atk = max(1, int(attack * SR))
    return [min(1.0, i / float(atk)) * math.exp(-i / float(decay * SR)) for i in range(length)]


def sine(length, freq, sweep=0.0):
    out, ph = [], 0.0
    for i in range(length):
        f = freq * (1.0 + sweep * i / float(length))
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph))
    return out


def mix(*layers):
    ln = max(len(l) for l in layers)
    out = [0.0] * ln
    for l in layers:
        for i, v in enumerate(l):
            out[i] += v
    return out


def scale(sig, k):
    return [s * k for s in sig]


def apply_env(sig, env):
    return [s * e for s, e in zip(sig, env)]


def gunshot():
    ln = int(0.42 * SR)
    crack = apply_env(highpass(n(ln), 0.35), env_exp(ln, 0.035, 0.0005))
    body = apply_env(lowpass(n(ln), 0.25), env_exp(ln, 0.09, 0.001))
    thump = apply_env(sine(ln, 120, -0.55), env_exp(ln, 0.12, 0.001))
    tail = apply_env(lowpass(n(ln), 0.08), env_exp(ln, 0.3, 0.02))
    return scale(mix(scale(crack, 0.75), scale(body, 0.55), scale(thump, 0.5), scale(tail, 0.18)), 0.92)


def enemy_gunshot():
    return scale(lowpass(gunshot(), 0.55), 0.85)


def dry_fire():
    ln = int(0.09 * SR)
    return apply_env(highpass(n(ln), 0.5), env_exp(ln, 0.012, 0.0004))


def reload_sound():
    ln = int(1.05 * SR)
    out = [0.0] * ln
    for t, dec, amp, hp in ((0.02, 0.02, 0.8, 0.55), (0.28, 0.03, 0.6, 0.4),
                            (0.55, 0.025, 0.75, 0.5), (0.8, 0.035, 0.9, 0.45)):
        st = int(t * SR)
        cl = apply_env(highpass(n(int(0.12 * SR)), hp), env_exp(int(0.12 * SR), dec, 0.0004))
        for i, v in enumerate(cl):
            if st + i < ln:
                out[st + i] += v * amp
    return out


def footstep():
    ln = int(0.16 * SR)
    tap = apply_env(lowpass(n(ln), 0.4), env_exp(ln, 0.028, 0.001))
    low = apply_env(sine(ln, 90, -0.3), env_exp(ln, 0.035, 0.001))
    return scale(mix(scale(tap, 0.55), scale(low, 0.3)), 0.55)


def impact_wall():
    ln = int(0.18 * SR)
    tick = apply_env(highpass(n(ln), 0.45), env_exp(ln, 0.02, 0.0004))
    dust = apply_env(lowpass(n(ln), 0.2), env_exp(ln, 0.07, 0.003))
    return scale(mix(scale(tick, 0.7), scale(dust, 0.3)), 0.7)


def impact_flesh():
    ln = int(0.22 * SR)
    thud = apply_env(lowpass(n(ln), 0.18), env_exp(ln, 0.05, 0.001))
    low = apply_env(sine(ln, 150, -0.5), env_exp(ln, 0.06, 0.001))
    return scale(mix(scale(thud, 0.65), scale(low, 0.4)), 0.8)


def hurt():
    ln = int(0.35 * SR)
    breath = apply_env(lowpass(n(ln), 0.12), env_exp(ln, 0.12, 0.01))
    tone = apply_env(sine(ln, 210, -0.25), env_exp(ln, 0.1, 0.01))
    return scale(mix(scale(breath, 0.5), scale(tone, 0.25)), 0.7)


def death_fall():
    ln = int(0.6 * SR)
    thud = apply_env(lowpass(n(ln), 0.12), env_exp(ln, 0.15, 0.002))
    low = apply_env(sine(ln, 70, -0.4), env_exp(ln, 0.2, 0.002))
    return scale(mix(scale(thud, 0.6), scale(low, 0.5)), 0.85)


def cam_beep():
    ln = int(0.12 * SR)
    return scale(apply_env(sine(ln, 1760), env_exp(ln, 0.03, 0.002)), 0.35)


def cam_click():
    ln = int(0.06 * SR)
    return scale(apply_env(highpass(n(ln), 0.6), env_exp(ln, 0.008, 0.0003)), 0.4)


def ambience():
    ln = int(4.0 * SR)
    hum = []
    for i in range(ln):
        t = i / float(SR)
        v = 0.0
        for f, a in ((50.0, 0.5), (100.0, 0.22), (153.0, 0.1), (201.0, 0.05)):
            v += a * math.sin(2 * math.pi * f * t)
        hum.append(v * 0.16)
    air = scale(lowpass(n(ln), 0.05), 0.7)
    sig = mix(hum, air)
    fade = int(0.08 * SR)
    for i in range(fade):
        k = i / float(fade)
        sig[i] = sig[i] * k + sig[ln - fade + i] * (1 - k)
    return scale(sig, 0.5)


SOUNDS = {
    "gunshot.wav": gunshot,
    "gunshot_enemy.wav": enemy_gunshot,
    "dry_fire.wav": dry_fire,
    "reload.wav": reload_sound,
    "footstep.wav": footstep,
    "impact_wall.wav": impact_wall,
    "impact_flesh.wav": impact_flesh,
    "hurt.wav": hurt,
    "death.wav": death_fall,
    "cam_beep.wav": cam_beep,
    "cam_click.wav": cam_click,
    "ambience.wav": ambience,
}

if __name__ == "__main__":
    for name, fn in SOUNDS.items():
        path, dur = write_wav(name, fn())
        print("%-20s %5.2fs %8d bytes" % (name, dur, os.path.getsize(path)))
