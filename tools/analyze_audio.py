#!/usr/bin/env python3
"""Beat / onset analysis for Bad Apple soundtrack.

Outputs assets/beats.txt: one line per detected event:
  type<TAB>time_seconds<TAB>strength
where type in {beat, onset, kick, snare}.

Pipeline:
  1) decode ogg via ffmpeg to mono 22050 Hz float32
  2) split into low (kick) / mid (snare) / high (hat) bands
  3) per-band onset detection via spectral-flux peaks
  4) global beat grid: BPM estimate via autocorrelation of full-band onset envelope
  5) snap grid to nearest strong onset for phase alignment
"""
from __future__ import annotations
import os
import sys
import subprocess
import numpy as np
from scipy.signal import butter, sosfilt, find_peaks

SR = 22050
HOP = 512  # ~23 ms

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC  = os.path.join(ROOT, "assets", "badapple.ogg")
OUT  = os.path.join(ROOT, "assets", "beats.txt")


def decode(path: str) -> np.ndarray:
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-ac", "1", "-ar", str(SR), "-f", "f32le", "-",
    ])
    return np.frombuffer(raw, dtype=np.float32).copy()


def band(y, lo, hi):
    sos = butter(4, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, y).astype(np.float32)


def envelope(y):
    n = len(y) // HOP
    e = np.empty(n, dtype=np.float32)
    for i in range(n):
        seg = y[i*HOP:(i+1)*HOP]
        e[i] = float(np.sqrt(np.mean(seg * seg) + 1e-12))
    # log compression then smoothing then derivative
    e = np.log1p(e * 50.0)
    # half-wave rectified diff = onset envelope
    d = np.diff(e, prepend=e[0])
    d = np.maximum(d, 0.0)
    # local mean subtract
    k = 8
    m = np.convolve(d, np.ones(k)/k, mode="same")
    o = np.maximum(d - m, 0.0)
    return e, o


def pick(o, mindist_frames, h):
    # adaptive height = h * local std
    win = 30
    out = []
    cs = np.cumsum(o**2)
    for i in range(1, len(o)):
        a = max(0, i - win); b = min(len(o)-1, i + win)
        loc = float(np.sqrt(max(cs[b] - cs[a], 0.0) / max(b - a, 1)))
        thr = h * loc + 1e-3
        if o[i] > thr and o[i] > o[i-1] and (i+1>=len(o) or o[i] >= o[i+1]):
            if not out or i - out[-1] >= mindist_frames:
                out.append(i)
    return np.array(out, dtype=np.int64)


def estimate_bpm(o):
    # autocorrelation in plausible BPM range 80..180
    fps = SR / HOP
    lags = np.arange(int(fps * 60 / 180), int(fps * 60 / 80))
    o = o - o.mean()
    a = np.correlate(o, o, mode="full")
    a = a[len(o)-1:]
    s = a[lags]
    best = lags[int(np.argmax(s))]
    bpm = 60.0 * fps / best
    return bpm, float(s.max())


def main():
    y = decode(SRC)
    dur = len(y) / SR
    print(f"decoded {dur:.2f}s @ {SR}Hz")

    low = band(y, 30, 180)        # kick
    mid = band(y, 200, 1500)      # snare/clap
    hi  = band(y, 4000, 9000)     # hat / high

    _, o_full = envelope(y)
    _, o_low  = envelope(low)
    _, o_mid  = envelope(mid)
    _, o_hi   = envelope(hi)

    bpm, _ = estimate_bpm(o_full)
    print(f"estimated bpm: {bpm:.2f}")

    # frames -> seconds helper
    def fr2s(fr):
        return fr * HOP / SR

    # onset peaks per band
    fps = SR / HOP
    peaks_low = pick(o_low, int(fps * 0.10), 1.4)
    peaks_mid = pick(o_mid, int(fps * 0.10), 1.3)
    peaks_hi  = pick(o_hi,  int(fps * 0.06), 1.2)
    peaks_any = pick(o_full, int(fps * 0.07), 1.2)
    print(f"onsets: kick={len(peaks_low)} snare={len(peaks_mid)} hat={len(peaks_hi)} any={len(peaks_any)}")

    # build beat grid using BPM, phase-aligned to first kick
    period = 60.0 / bpm
    if len(peaks_low):
        phase = fr2s(peaks_low[0]) % period
    else:
        phase = 0.0
    grid = np.arange(phase, dur, period)
    # snap each grid time to nearest strong onset within ±period/4
    snap_window = period / 4
    onset_times = np.array([fr2s(p) for p in peaks_any])
    snapped = []
    for t in grid:
        if len(onset_times):
            j = int(np.argmin(np.abs(onset_times - t)))
            if abs(onset_times[j] - t) <= snap_window:
                snapped.append(onset_times[j])
                continue
        snapped.append(float(t))
    beats = np.array(snapped)
    print(f"beat grid: {len(beats)} beats over {dur:.1f}s")

    # write output
    rows = []
    for t in beats:
        rows.append(("beat", float(t), 1.0))
    for p in peaks_low:
        rows.append(("kick", fr2s(p), float(o_low[p])))
    for p in peaks_mid:
        rows.append(("snare", fr2s(p), float(o_mid[p])))
    for p in peaks_hi:
        rows.append(("hat", fr2s(p), float(o_hi[p])))
    for p in peaks_any:
        rows.append(("onset", fr2s(p), float(o_full[p])))

    rows.sort(key=lambda r: r[1])

    with open(OUT, "w") as f:
        f.write(f"# bpm={bpm:.4f}\n")
        f.write(f"# duration={dur:.4f}\n")
        for typ, t, s in rows:
            f.write(f"{typ}\t{t:.4f}\t{s:.4f}\n")
    print(f"wrote {OUT} ({len(rows)} events)")


if __name__ == "__main__":
    main()
