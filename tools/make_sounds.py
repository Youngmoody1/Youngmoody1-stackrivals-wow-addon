"""Renders the StackRivals sound set to OGG for the WoW addon.
Same recipes as the web game's synthesized Web Audio sounds (src/game/sfx.ts): sine/square/saw
tones with pitch glides, filtered noise and sub-bass thumps. Everything is generated here, so
there is nothing to license."""
import subprocess, sys, os
import numpy as np

SR = 44100
rng = np.random.default_rng(7)  # fixed seed: reproducible files

def env(n, a, curve="exp"):
    t = np.arange(n) / SR
    att = min(n, int(0.008 * SR))
    e = np.ones(n) * a
    e[:att] = np.linspace(0.0001, a, att)
    rest = n - att
    if rest > 0:
        e[att:] = a * (np.geomspace(1, 0.0001 / a, rest) if curve == "exp" else np.linspace(1, 0.0001 / a, rest))
    return e

def osc(kind, f0, f1, d):
    n = int(d * SR)
    f = np.geomspace(f0, max(20, f1), n) if f1 else np.full(n, f0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if kind == "sine": w = np.sin(ph)
    elif kind == "square": w = np.sign(np.sin(ph)) * 0.6
    elif kind == "triangle": w = 2 / np.pi * np.arcsin(np.sin(ph))
    else: w = 2 * ((ph / (2 * np.pi)) % 1) - 1; w *= 0.6
    return w

def lowpass(x, fc):
    # one-pole low-pass with per-sample cutoff
    fc = np.broadcast_to(fc, x.shape)
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.zeros_like(x); prev = 0.0
    for i in range(len(x)):
        prev = (1 - a[i]) * x[i] + a[i] * prev; y[i] = prev
    return y

class Mix:
    def __init__(self, d): self.buf = np.zeros(int(d * SR) + SR // 10)
    def add(self, sig, at=0.0):
        i = int(at * SR); j = min(len(self.buf), i + len(sig)); self.buf[i:j] += sig[: j - i]
    def tone(self, f, d, f1=None, t="square", a=0.08, at=0.0, curve="exp"):
        w = osc(t, f, f1, d); self.add(w * env(len(w), a, curve), at)
    def noise(self, d, a=0.1, at=0.0, f0=2500, f1=150):
        n = int(d * SR); w = rng.uniform(-1, 1, n) * np.linspace(1, 0, n)
        w = lowpass(w, np.geomspace(f0, f1, n)); self.add(w * env(n, a) * 2.5, at)
    def sub(self, f=120, f1=32, d=0.8, a=0.9, at=0.0):
        w = np.tanh(2 * osc("sine", f, f1, d)); self.add(w * env(len(w), a), at)
    def boom(self, f=120, d=0.9, a=0.5, at=0.0):
        self.sub(f, 30, d, a, at); self.noise(min(0.3, d * 0.4), a * 0.8, at, 3000, 200); self.noise(d, a * 0.6, at + 0.03, 500, 60)
    def write(self, path, gain=1.0):
        x = self.buf * gain
        peak = np.max(np.abs(x)) or 1
        if peak > 0.95: x = x / peak * 0.95
        nz = np.nonzero(np.abs(x) > 1e-4)[0]
        x = x[: (nz[-1] + 1 if len(nz) else len(x))]
        pcm = (x * 32767).astype(np.int16).tobytes()
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                        "-c:a", "libvorbis", "-q:a", "4", path], input=pcm, check=True)

out = sys.argv[1]; os.makedirs(out, exist_ok=True)
def mk(name, d, fn, gain=1.0):
    m = Mix(d); fn(m); m.write(f"{out}/{name}.ogg", gain)

mk("rotate", 0.08, lambda m: m.tone(360, 0.04, 520, "sine", 0.05))
mk("hold", 0.12, lambda m: m.tone(330, 0.09, 220, "sine", 0.12))
mk("lock", 0.08, lambda m: m.tone(100, 0.05, 70, "triangle", 0.15))
def hard(m): m.tone(150, 0.12, 45, "sine", 0.35); m.noise(0.06, 0.12, 0, 2500, 300)
mk("harddrop", 0.2, hard)
for n in range(1, 5):
    def clear(m, n=n):
        m.tone(170 + n * 10, 0.16 + n * 0.04, 40, "sine", 0.18 + n * 0.05)
        m.noise(0.12 + n * 0.05, 0.1 + n * 0.05, 0, 2500, 150)
        if n >= 4:
            m.boom(90, 1.0, 0.6, 0.05)
            for k, mul in enumerate([1, 1.25, 1.5, 2]): m.tone(523 * mul, 0.7, None, "sawtooth", 0.06, 0.15 + k * 0.03)
    mk(f"clear{n}", 1.3 if n == 4 else 0.4, clear, 1.6)
def hype(m):
    for i in range(4):
        m.tone(660 * 1.19 ** i, 0.25 + i * 0.04, None, "sine", 0.1, i * 0.07)
        m.tone(660 * 1.19 ** i * 2, 0.2, None, "triangle", 0.03, i * 0.07)
mk("combo", 0.7, hype)
def tick(m): m.tone(520, 0.07, 380, "sine", 0.18); m.noise(0.05, 0.06, 0, 1800, 900)
mk("count", 0.12, tick)
def go(m): m.tone(180, 0.3, 45, "sine", 0.4); m.noise(0.25, 0.25, 0, 3000, 200); m.tone(1200, 0.12, None, "sine", 0.08, 0.02)
mk("go", 0.4, go)
def over(m):
    m.boom(100, 1.4, 0.7)
    for i, f in enumerate([392, 349, 311, 262]): m.tone(f, 0.4, f * 0.94, "sawtooth", 0.08, 0.15 + i * 0.22)
mk("gameover", 1.6, over)
def win(m):
    for i, f in enumerate([523, 659, 784, 1046, 1318]): m.tone(f, 0.7 if i == 4 else 0.16, None, "square", 0.07, i * 0.1)
mk("record", 1.2, win)
def level(m):
    for i in range(3): m.tone(880 + i * 220, 0.2, None, "triangle", 0.09, i * 0.08)
mk("levelup", 0.5, level)
print("ok")
