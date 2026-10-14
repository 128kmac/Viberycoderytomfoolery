# /// script
# requires-python = ">=3.10"
# dependencies = ["librosa>=0.10.2", "numpy", "scipy", "soundfile", "scikit-learn", "onnxruntime"]
# ///
"""Song analyzer: everything a music video needs to be cut against the song.

    uv run tools/song-analyzer/analyze.py SONG.mp3 --out DIR [--start 1:57] [--end 3:06]
        [--fps 60] [--snap-start] [--excerpt-wav FILE.wav] [--lyrics LINES.txt] [--audio-src URL]

Measures, over the whole song (so the excerpt is read in context):
  beat     tempo, a fitted beat grid, downbeats/bars (local phase checked), drum hits
           (kick, snare, crash) and hat density
  tune     key (Krumhansl-Kessler), chord per beat (maj / min / power), roman numerals,
           the vocal melody as notes (pYIN on an extracted centre/foreground vocal)
  loud     EBU R128 style momentary + short-term loudness, integrated loudness,
           a quiet / medium / loud / peak class per bar, builds, impacts, stops
  structure  novelty-based sections snapped to bars, clustered into repeats (A/B/C) and named
  vocals   phrase on/off times, syllable onsets, pitch range, held notes. Words are not
           transcribed; --lyrics aligns a lyric sheet you supply (one line per sung line)
           to the detected phrases.
  instruments  per-bar presence of kick, snare, cymbals, bass, wide distorted guitars,
           clean sustained layer (strings/synth/keys) and vocals (DSP estimates, no ML)

Writes to --out:
  analysis.json   whole song, absolute song times
  excerpt.json    the same, cut to [start, end] with times relative to start
  cues.json       per-video-frame envelopes (0..1) for audio-driven animation
  beats.json      the grid in the motion-reel format (offset/period relative to start)
  report.html     an interactive timeline of all of it (plays the audio if --audio-src)
"""

import argparse
import json
import math
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf
from scipy import ndimage, signal
from scipy.cluster import hierarchy
from scipy.spatial.distance import pdist

SR = 44100
HOP = 441                 # 100 analysis frames per second
NFFT = 2048
FR = SR / HOP
SR_V = 22050              # vocal / tonal pipeline
HOP_V = 512
NOTE = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


# ------------------------------------------------------------------ small helpers

def parse_time(s):
    if s is None:
        return None
    s = str(s)
    if ":" in s:
        m, x = s.split(":")
        return int(m) * 60 + float(x)
    return float(s)


def clean(o):
    """JSON-safe copy: NaN/inf (e.g. the loudness of a silent bar) become null."""
    if isinstance(o, float):
        return o if math.isfinite(o) else None
    if isinstance(o, dict):
        return {k: clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [clean(v) for v in o]
    return o


def mmss(t):
    return f"{int(t // 60)}:{t % 60:05.2f}"


def db(x):
    return 10 * np.log10(np.maximum(x, 1e-12))


def norm01(x, lo_pct=5, hi_pct=99, ref=None):
    """Robust 0..1 scaling against percentiles of ref (the whole song)."""
    r = x if ref is None else ref
    lo, hi = np.nanpercentile(r, lo_pct), np.nanpercentile(r, hi_pct)
    return np.clip((x - lo) / max(hi - lo, 1e-9), 0, 1)


def smooth(x, n):
    if n <= 1:
        return x
    return ndimage.uniform_filter1d(x, int(n), mode="nearest")


def frames_of(t, rate=FR):
    return int(round(t * rate))


def peaks(env, rate, min_gap, rel=0.12, k=1.4, win=0.5):
    """Peak-pick an onset envelope: local max over min_gap, above an adaptive threshold
    (k x local mean over +-win s) and above rel x the 99th percentile."""
    e = np.asarray(env, float)
    top = np.percentile(e, 99.5) + 1e-9
    w = max(1, int(win * rate))
    local = ndimage.uniform_filter1d(e, 2 * w + 1, mode="nearest")
    g = max(1, int(min_gap * rate))
    mx = ndimage.maximum_filter1d(e, 2 * g + 1, mode="nearest")
    idx = np.where((e == mx) & (e > k * local) & (e > rel * top))[0]
    # enforce the gap (plateaus can give neighbours)
    out = []
    for i in idx:
        if not out or i - out[-1] >= g:
            out.append(i)
    return np.array(out, int), e[out] / top if out else np.array([])


def band_idx(freqs, lo, hi):
    return (freqs >= lo) & (freqs < hi)


def band_db(M, freqs, lo, hi):
    return db((M[band_idx(freqs, lo, hi)] ** 2).sum(axis=0))


def band_flux(M, freqs, lo, hi):
    """Spectral flux (positive log-magnitude change) inside a band."""
    L = np.log1p(100 * M[band_idx(freqs, lo, hi)])
    d = np.diff(L, axis=1, prepend=L[:, :1])
    return np.maximum(d, 0).mean(axis=0)


# ------------------------------------------------------------------ loudness (BS.1770 / R128)

def k_weight(x, fs):
    """BS.1770 K-weighting (shelf + RLB high-pass), coefficients derived for any rate."""
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = math.tan(math.pi * f0 / fs)
    Vh = 10 ** (G / 20)
    Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / fs)
    a0 = 1 + K / Q + K * K
    a2 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    return signal.lfilter([1, -2, 1], a2, signal.lfilter(b1, a1, x, axis=-1), axis=-1)


def loudness_curves(y):
    """Momentary (400 ms) and short-term (3 s) loudness at 100 Hz, centred windows, plus
    gated integrated loudness and loudness range."""
    z = (k_weight(y, SR) ** 2).sum(axis=0)
    c = np.concatenate([[0], np.cumsum(z)])
    n = len(z)
    centers = np.arange(0, n, HOP)

    def win(sec):
        h = int(sec * SR / 2)
        a = np.clip(centers - h, 0, n)
        b = np.clip(centers + h, 0, n)
        return -0.691 + db((c[b] - c[a]) / np.maximum(b - a, 1))

    mom, st = win(0.4), win(3.0)
    # integrated: 400 ms blocks, 75 % overlap, absolute gate -70, relative gate -10
    blk, step = int(0.4 * SR), int(0.1 * SR)
    starts = np.arange(0, n - blk, step)
    bl = (c[starts + blk] - c[starts]) / blk
    L = -0.691 + db(bl)
    g1 = bl[L > -70]
    rel = -0.691 + db(g1.mean()) - 10
    integ = -0.691 + db(bl[(L > -70) & (L > rel)].mean())
    # LRA from short-term values (gated -70 abs, -20 rel), 10th..95th percentile
    sts = st[st > -70]
    sts = sts[sts > (-0.691 + db(np.mean(10 ** ((sts + 0.691) / 10))) - 20)]
    lra = float(np.percentile(sts, 95) - np.percentile(sts, 10)) if len(sts) else 0.0
    return mom, st, float(integ), lra


# ------------------------------------------------------------------ beat grid

def rise(L, lag=3, sm=2):
    """Onset function as a level rise in dB over lag frames (robust on dense, compressed mixes,
    where per-bin spectral flux is mostly noise)."""
    L = ndimage.uniform_filter1d(L, sm, mode="nearest")
    r = np.zeros_like(L)
    r[lag:] = L[lag:] - L[:-lag]
    return np.maximum(r, 0)


def pick(r, gap, thr):
    g = max(1, int(gap * FR))
    mx = ndimage.maximum_filter1d(r, 2 * g + 1, mode="nearest")
    idx = np.where((r == mx) & (r > thr))[0]
    out = []
    for i in idx:
        if not out or i - out[-1] >= g:
            out.append(i)
    return np.array(out, int)


# A dB-rise onset peaks a little after the attack starts (the rise is measured over 3 frames).
# Measured against librosa's backtracked onsets on a dense rock mix, the bias is ~12-16 ms; take it off.
ONSET_LAT = 0.012


def refine(env, idx):
    """Sub-frame peak times by parabolic interpolation, latency-compensated."""
    out = []
    for i in idx:
        if 0 < i < len(env) - 1:
            a, b, c = env[i - 1], env[i], env[i + 1]
            den = a - 2 * b + c
            out.append(i + (0.5 * (a - c) / den if den != 0 else 0.0))
        else:
            out.append(float(i))
    return np.array(out) / FR - ONSET_LAT


def phase_coherence(t, w, p):
    z = np.sum(w * np.exp(2j * np.pi * t / p))
    return np.abs(z) / (w.sum() + 1e-12), (np.angle(z) / (2 * np.pi) * p) % p


def beat_grid(onset_env, t_on, w_on, duration):
    """Constant-tempo grid by phase coherence of drum onsets on the 8th-note grid (on-beats and
    off-beats both line up there, so syncopated kicks don't cancel), around librosa's tempo
    estimate. Local 8 s windows report how far the band strays from the grid; when a stretch
    strays (no click / tempo change) the grid falls back to tracked beats there."""
    t_prior = float(np.atleast_1d(librosa.feature.tempo(onset_envelope=onset_env, sr=SR, hop_length=HOP,
                                                         start_bpm=120))[0])
    if t_prior < 80:
        t_prior *= 2
    if t_prior > 180:
        t_prior /= 2
    p0 = 60 / t_prior
    best = (-1, p0)
    for p in np.arange(p0 * 0.96, p0 * 1.04, 2e-5):
        r, _ = phase_coherence(t_on, w_on, p / 2)
        if r > best[0]:
            best = (r, p)
    R, per = best
    _, off8 = phase_coherence(t_on, w_on, per / 2)
    dev = []
    for a in np.arange(0, duration, 8.0):
        m = (t_on >= a) & (t_on < a + 8)
        if m.sum() < 6:
            dev.append((float(a), None, 0.0))
            continue
        r, lo = phase_coherence(t_on[m], w_on[m], per / 2)
        d = ((lo - off8 + per / 4) % (per / 2) - per / 4) * 1000
        dev.append((float(a), round(float(d), 1), round(float(r), 2)))
    good = [abs(d) for _, d, r in dev if d is not None and r > 0.4]
    constant = R > 0.45 and len(good) > 0 and np.median(good) < 15
    return {
        "bpm": round(60 / per, 3), "period": float(per), "offset8": float(off8), "coherence": round(float(R), 3),
        "constant_tempo": bool(constant), "local_dev_ms": dev,
        "fit_residual_ms": round(float(np.sqrt(np.mean(np.square(good)))) if good else 0.0, 2),
    }


def strength_at(times, env, rate, w=0.04):
    """Max of an envelope within +-w s of each time."""
    out = []
    n = len(env)
    for t in times:
        a, b = max(0, int((t - w) * rate)), min(n, int((t + w) * rate) + 1)
        out.append(float(env[a:b].max()) if b > a else 0.0)
    return np.array(out)


def downbeat_phase(beats, kick_env, snare_env, chroma_change):
    """Per beat, a score for 'this beat is a 1': kick here, snare on the 2 and 4, harmony moves.
    Evaluated in sliding 8-bar windows so an odd-length bar re-anchors the bar lines."""
    kb = strength_at(beats, kick_env, FR)
    sb = strength_at(beats, snare_env, FR)
    kb, sb = kb / (kb.max() + 1e-9), sb / (sb.max() + 1e-9)
    cc = chroma_change / (chroma_change.max() + 1e-9)
    n = len(beats)

    def roll(a, s):
        return np.concatenate([a[s:], np.zeros(s)])

    one = 1.0 * kb + 0.8 * roll(sb, 1) + 0.8 * roll(sb, 3) - 0.6 * sb + 0.7 * cc
    glob = int(np.argmax([one[p::4].mean() for p in range(4)]))
    # local phase per 32-beat window, accepted only when clearly better than the global one
    phase = np.full(n, glob)
    W = 32
    for a in range(0, n, 8):
        seg = slice(max(0, a - W // 2), min(n, a + W // 2))
        idx = np.arange(n)[seg]
        sc = [one[idx[(idx - p) % 4 == 0]].mean() if np.any((idx - p) % 4 == 0) else -9 for p in range(4)]
        best = int(np.argmax(sc))
        if sc[best] > sc[glob] * 1.35:
            phase[a:a + 8] = best
    phase = ndimage.median_filter(phase, size=17, mode="nearest")
    downs = [i for i in range(n) if (i - phase[i]) % 4 == 0]
    return np.array(downs, int), glob


# ------------------------------------------------------------------ tonal: key + chords

KK_MAJ = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
KK_MIN = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])


def key_estimate(chroma_mean):
    res = []
    for r in range(12):
        for mode, prof in (("major", KK_MAJ), ("minor", KK_MIN)):
            res.append((float(np.corrcoef(chroma_mean, np.roll(prof, r))[0, 1]), r, mode))
    res.sort(reverse=True)
    (c, r, m), (c2, r2, m2) = res[0], res[1]
    return {"tonic": NOTE[r], "mode": m, "name": f"{NOTE[r]} {m}", "confidence": round(c, 3),
            "runner_up": f"{NOTE[r2]} {m2}", "runner_up_confidence": round(c2, 3), "tonic_pc": r}


def chord_templates():
    names, T = [], []
    for r in range(12):
        for q, iv, w in (("", (0, 4, 7), (1, .85, .9)), ("m", (0, 3, 7), (1, .85, .9)), ("5", (0, 7), (1, .95))):
            v = np.zeros(12)
            for i, ww in zip(iv, w):
                v[(r + i) % 12] = ww
            names.append(NOTE[r] + q)
            T.append(v / np.linalg.norm(v))
    return names, np.array(T)


ROMAN = ["I", "bII", "II", "bIII", "III", "IV", "#IV", "V", "bVI", "VI", "bVII", "VII"]


def roman(chord, key):
    if chord == "N":
        return "N"
    root = chord.rstrip("m5")
    q = chord[len(root):]
    deg = (NOTE.index(root) - key["tonic_pc"]) % 12
    r = ROMAN[deg]
    if q == "m":
        r = r.lower()
    return r + ("5" if q == "5" else "")


def chords_per_beat(chroma_b, energy_b):
    names, T = chord_templates()
    C = chroma_b / (np.linalg.norm(chroma_b, axis=0, keepdims=True) + 1e-9)
    sim = T @ C                                     # (36, beats)
    # power chord only when the third is genuinely weak: small handicap for the ambiguous template
    sim[2::3] -= 0.03
    nch = np.full((1, sim.shape[1]), 0.55)          # "no chord" baseline
    nch[0, energy_b < np.percentile(energy_b, 8)] = 1.2
    S = np.vstack([sim, nch])
    P = np.exp(12 * S)
    P /= P.sum(axis=0, keepdims=True)
    trans = librosa.sequence.transition_loop(S.shape[0], 0.75)
    path = librosa.sequence.viterbi_discriminative(P, trans)
    lab = [names[i] if i < len(names) else "N" for i in path]
    conf = [float(sim[i, j]) if i < len(names) else 0.0 for j, i in enumerate(path)]
    return lab, conf


# ------------------------------------------------------------------ vocals

def vocal_pipeline(y):
    """Lead-vocal estimate: a centre-panning mask (bins where L and R agree in level and phase,
    which is where a lead vocal sits and double-tracked guitars don't), then REPET-SIM to drop
    what repeats (riffs, drum loops), then pYIN on the result."""
    l = librosa.resample(y[0], orig_sr=SR, target_sr=SR_V)
    r = librosa.resample(y[1], orig_sr=SR, target_sr=SR_V)
    XL = librosa.stft(l, n_fft=2048, hop_length=HOP_V)
    XR = librosa.stft(r, n_fft=2048, hop_length=HOP_V)
    XM = (XL + XR) / 2
    sim = 2 * np.abs(XL * np.conj(XR)) / (np.abs(XL) ** 2 + np.abs(XR) ** 2 + 1e-9)
    mag = np.abs(XM) * sim ** 8
    phase = np.exp(1j * np.angle(XM))
    width = int(librosa.time_to_frames(2.0, sr=SR_V, hop_length=HOP_V))
    rep = librosa.decompose.nn_filter(mag, aggregate=np.median, metric="cosine", width=width)
    rep = np.minimum(mag, rep)
    mask = librosa.util.softmask(mag - rep, 2 * rep, power=2)
    fg = mask * mag
    yv = librosa.istft(fg * phase, hop_length=HOP_V, length=len(l))
    f0, vflag, vprob = librosa.pyin(yv, fmin=90, fmax=1100, sr=SR_V, frame_length=2048, hop_length=HOP_V,
                                    fill_na=np.nan)
    freqs = librosa.fft_frequencies(sr=SR_V, n_fft=2048)
    e = band_db(fg, freqs, 250, 3500)
    flux = rise(band_db(fg, freqs, 300, 4000), lag=2)
    t = librosa.frames_to_time(np.arange(fg.shape[1]), sr=SR_V, hop_length=HOP_V)
    n = min(len(t), len(f0))
    return t[:n], e[:n], f0[:n], vprob[:n], flux[:n], fg


def vocal_from_stem(voc):
    """Features of a separated vocal stem: level, pYIN pitch, onset rises."""
    m = librosa.resample(voc.mean(axis=0), orig_sr=SR, target_sr=SR_V)
    S = np.abs(librosa.stft(m, n_fft=2048, hop_length=HOP_V))
    freqs = librosa.fft_frequencies(sr=SR_V, n_fft=2048)
    e = band_db(S, freqs, 120, 6000)
    f0, _, vprob = librosa.pyin(m, fmin=80, fmax=1100, sr=SR_V, frame_length=2048, hop_length=HOP_V, fill_na=np.nan)
    flux = rise(band_db(S, freqs, 200, 5000), lag=2)
    t = librosa.frames_to_time(np.arange(S.shape[1]), sr=SR_V, hop_length=HOP_V)
    n = min(len(t), len(f0))
    return t[:n], e[:n], f0[:n], vprob[:n], flux[:n]


def otsu(x, bins=128):
    h, edges = np.histogram(x, bins=bins)
    c = (edges[:-1] + edges[1:]) / 2
    w0 = np.cumsum(h)
    w1 = w0[-1] - w0
    m0 = np.cumsum(h * c) / np.maximum(w0, 1)
    m1 = (np.sum(h * c) - np.cumsum(h * c)) / np.maximum(w1, 1)
    return float(c[np.argmax(w0 * w1 * (m0 - m1) ** 2)])


def vocal_phrases(tv, ev, f0, vprob, flux, song_dur, stem=False):
    rate = 1 / (tv[1] - tv[0])
    en = norm01(ev, 10, 97)
    if stem:
        # a separated stem: silence is easy (Otsu split of the level), but dense singing only
        # breaks for breaths, so a phrase also ends where the level dips >= 12 dB under its
        # running 1 s peak for >= 90 ms
        lvl = smooth(ev, max(1, int(0.03 * rate)))
        thr = otsu(lvl[lvl > np.percentile(lvl, 1)])
        loc = smooth(ndimage.maximum_filter1d(lvl, int(1.0 * rate), mode="nearest"), int(0.2 * rate))
        gap = (lvl < thr) | (lvl < loc - 12)
        gap = ndimage.binary_opening(gap, structure=np.ones(max(1, int(0.09 * rate))))
        act = ~gap
        act = ndimage.binary_opening(act, structure=np.ones(max(1, int(0.15 * rate))))
        score = np.clip((lvl - thr) / (np.percentile(lvl, 95) - thr + 1e-9), 0, 1) * act
    else:
        vp = smooth(np.nan_to_num(vprob), int(0.12 * rate))
        score = smooth(0.55 * en + 0.45 * vp, int(0.08 * rate))
        on, off = 0.50, 0.36
        act = np.zeros(len(score), bool)
        state = False
        for i, s in enumerate(score):
            state = s > on if not state else s > off
            act[i] = state
        # close short gaps, drop blips
        act = ndimage.binary_closing(act, structure=np.ones(int(0.3 * rate)))
    lab, n = ndimage.label(act)
    phrases = []
    for k in range(1, n + 1):
        idx = np.where(lab == k)[0]
        a, b = tv[idx[0]], tv[idx[-1]]
        if b - a < (0.25 if stem else 0.35):
            continue
        ff = f0[idx]
        ff = ff[np.isfinite(ff)]
        midi = librosa.hz_to_midi(ff) if len(ff) else np.array([])
        # syllable-ish onsets: flux peaks inside the phrase
        fl = flux[idx]
        g = max(1, int(0.1 * rate))
        mx = ndimage.maximum_filter1d(fl, 2 * g + 1, mode="nearest")
        pk = np.where((fl == mx) & (fl > 4.0))[0]
        sy = [round(float(tv[idx[0] + p]), 3) for p in pk]
        if not sy or sy[0] - a > 0.08:
            sy = [round(float(a), 3)] + sy
        phrases.append({
            "start": round(float(a), 3), "end": round(float(b), 3), "dur": round(float(b - a), 3),
            "level": round(float(en[idx].mean()), 3), "peak_level": round(float(en[idx].max()), 3),
            "pitch_median": NOTE[int(round(np.median(midi))) % 12] + str(int(round(np.median(midi))) // 12 - 1) if len(midi) else None,
            "midi_median": round(float(np.median(midi)), 2) if len(midi) else None,
            "midi_max": round(float(np.percentile(midi, 95)), 2) if len(midi) else None,
            "syllable_onsets": sy, "syllables_est": len(sy),
        })
    # intensity class against the singer's own range
    if phrases:
        mm = np.array([p["midi_median"] or 0 for p in phrases])
        lv = np.array([p["level"] for p in phrases])
        hi_p, hi_l = np.percentile(mm[mm > 0], 66) if np.any(mm > 0) else 99, np.percentile(lv, 60)
        for p in phrases:
            high = (p["midi_median"] or 0) >= hi_p
            loud = p["level"] >= hi_l
            p["intensity"] = "belted" if high and loud else "strong" if (high or loud) else "soft"
    return phrases, score


def group_lines(phrases, max_gap=0.2):
    """Sung lines: phrases joined across breaths shorter than max_gap."""
    lines = []
    for i, p in enumerate(phrases):
        if lines and p["start"] - lines[-1]["end"] < max_gap:
            L = lines[-1]
            L["end"] = p["end"]
            L["phrases"].append(i)
            L["syllables_est"] += p["syllables_est"]
            L["peak_level"] = max(L["peak_level"], p["peak_level"])
            if p.get("midi_max") is not None:
                L["midi_max"] = max(L["midi_max"] or 0, p["midi_max"])
        else:
            lines.append({"start": p["start"], "end": p["end"], "phrases": [i], "syllables_est": p["syllables_est"],
                          "peak_level": p["peak_level"], "midi_max": p.get("midi_max")})
    for L in lines:
        L["dur"] = round(L["end"] - L["start"], 3)
    return lines


def melody_notes(tv, f0, min_dur=0.08):
    midi = librosa.hz_to_midi(f0)
    good = np.isfinite(midi)
    mf = midi.copy()
    mf[~good] = 0
    mf = ndimage.median_filter(mf, size=5)
    notes, start = [], None
    rate = 1 / (tv[1] - tv[0])
    for i in range(len(mf) + 1):
        cur = mf[i] if i < len(mf) else 0
        if start is not None:
            seg = mf[start:i]
            if cur == 0 or abs(cur - np.median(seg)) > 0.75:
                if (i - start) / rate >= min_dur:
                    m = float(np.median(seg))
                    notes.append({"start": round(float(tv[start]), 3), "end": round(float(tv[i - 1]), 3),
                                  "midi": round(m, 2), "name": NOTE[int(round(m)) % 12] + str(int(round(m)) // 12 - 1)})
                start = None
        if start is None and cur > 0:
            start = i
    return notes


def align_lyrics(lines, phrases):
    """Partition the detected phrases (in order) into len(lines) contiguous groups so each
    group's syllable-onset count best matches the line's estimated syllables (DP)."""
    import re

    def syl(s):
        w = re.findall(r"[a-zA-Z']+", s.lower())
        return max(1, sum(max(1, len(re.findall(r"[aeiouy]+", x)) - (x.endswith("e") and len(x) > 2)) for x in w))

    L, P = len(lines), len(phrases)
    if L == 0 or P == 0:
        return []
    if P < L:   # fewer phrases than lines: give each phrase consecutive lines evenly
        out = []
        for i, line in enumerate(lines):
            p = phrases[min(P - 1, i * P // L)]
            out.append({"line": line, "start": p["start"], "end": p["end"], "phrases": [phrases.index(p)]})
        return out
    sy = np.array([p["syllables_est"] for p in phrases], float)
    cs = np.concatenate([[0], np.cumsum(sy)])
    ls = np.array([syl(x) for x in lines], float)
    INF = 1e18
    D = np.full((L + 1, P + 1), INF)
    B = np.zeros((L + 1, P + 1), int)
    D[0, 0] = 0
    for i in range(1, L + 1):
        for j in range(i, P - (L - i) + 1):
            for k in range(i - 1, j):
                c = D[i - 1, k] + np.log((cs[j] - cs[k] + 1) / (ls[i - 1] + 1)) ** 2
                if c < D[i, j]:
                    D[i, j], B[i, j] = c, k
    out, j = [], P
    for i in range(L, 0, -1):
        k = B[i, j]
        out.append({"line": lines[i - 1], "start": phrases[k]["start"], "end": phrases[j - 1]["end"],
                    "phrases": list(range(k, j))})
        j = k
    return out[::-1]


# ------------------------------------------------------------------ structure

def checkerboard(n):
    g = signal.windows.gaussian(2 * n, std=n / 2)
    G = np.outer(g, g)
    s = np.sign(np.arange(-n, n) + 0.5)
    return G * np.outer(s, s)


def segment(features_b, downs, n_beats, min_bars=4):
    X = (features_b - features_b.mean(axis=1, keepdims=True)) / (features_b.std(axis=1, keepdims=True) + 1e-9)
    Xn = X / (np.linalg.norm(X, axis=0, keepdims=True) + 1e-9)
    SSM = Xn.T @ Xn
    SSM = ndimage.uniform_filter(SSM, size=3)
    k = 16
    K = checkerboard(k)
    pad = np.pad(SSM, k, mode="edge")
    nov = np.array([(pad[i:i + 2 * k, i:i + 2 * k] * K).sum() for i in range(n_beats)])
    nov = np.maximum(nov, 0)
    nov /= nov.max() + 1e-9
    pk, _ = peaks(nov, 1.0, 4 * min_bars - 1, rel=0.12, k=1.05, win=16)
    cand = sorted(set(int(downs[np.argmin(np.abs(downs - p))]) for p in pk))
    # bound sections to whole bars; drop boundaries that make a section shorter than min_bars
    bounds = [0]
    for c in cand:
        if c - bounds[-1] >= 4 * min_bars:
            bounds.append(c)
    if n_beats - bounds[-1] < 4 * min_bars and len(bounds) > 1:
        bounds.pop()
    bounds.append(n_beats)
    return bounds, nov, SSM


def label_sections(bounds, features_b):
    segs = [(bounds[i], bounds[i + 1]) for i in range(len(bounds) - 1)]
    if len(segs) == 1:
        return ["A"]
    F = np.array([np.concatenate([features_b[:, a:b].mean(axis=1), features_b[:, a:b].std(axis=1) * 0.5]) for a, b in segs])
    F = (F - F.mean(0)) / (F.std(0) + 1e-9)
    Z = hierarchy.linkage(pdist(F, "cosine"), "average")
    lab = hierarchy.fcluster(Z, t=0.55, criterion="distance")
    letters, out = {}, []
    for l in lab:
        if l not in letters:
            letters[l] = "ABCDEFGHIJKLMNOP"[len(letters)]
        out.append(letters[l])
    return out


def name_sections(sections):
    """Heuristic names from energy, vocals and repetition."""
    if not sections:
        return
    loud = np.array([s["loudness_lufs"] for s in sections])
    hi = np.percentile(loud, 60)
    count = {}
    for s in sections:
        count[s["label"]] = count.get(s["label"], 0) + 1
    chorus_label = None
    cands = [(np.mean([x["loudness_lufs"] for x in sections if x["label"] == l]), l)
             for l in count if any(x["vocals"] > 0.3 for x in sections if x["label"] == l)]
    if cands:
        chorus_label = max(cands)[1]
    for i, s in enumerate(sections):
        if i == 0 and s["vocals"] < 0.2:
            s["name"] = "intro"
        elif i == len(sections) - 1 and (s["loudness_lufs"] < hi or s["vocals"] < 0.25):
            s["name"] = "outro"
        elif s["label"] == chorus_label:
            s["name"] = "chorus"
        elif s["vocals"] < 0.2:
            s["name"] = "instrumental"
        elif s["loudness_lufs"] < hi:
            s["name"] = "verse/bridge (quiet)"
        else:
            s["name"] = "verse/bridge (loud)"
    # a chorus-labelled run that is the last chorus gets called final chorus
    ch = [i for i, s in enumerate(sections) if s["name"] == "chorus"]
    if ch:
        sections[ch[-1]]["name"] = "final chorus"


# ------------------------------------------------------------------ main analysis

def analyze(path, start, end, fps, lyrics_path=None, cache=None, vocal_model=None, stems_dir=None):
    y, _ = librosa.load(path, sr=SR, mono=False)
    if y.ndim == 1:
        y = np.stack([y, y])
    dur = y.shape[1] / SR
    print(f"loaded {path}: {mmss(dur)} stereo @ {SR} Hz")
    voc = None
    if vocal_model:
        vc = Path(cache).with_name(".vocal_stem.npy") if cache else None
        if vc and vc.exists():
            voc = np.load(vc)
        else:
            from separate import separate_vocals
            voc = separate_vocals(y, vocal_model)
            if vc:
                np.save(vc, voc.astype(np.float32))
        if stems_dir:
            Path(stems_dir).mkdir(parents=True, exist_ok=True)
            sf.write(Path(stems_dir) / "vocals.wav", voc.T, SR, subtype="PCM_16")
            sf.write(Path(stems_dir) / "instrumental.wav", (y - voc).T, SR, subtype="PCM_16")
    # instruments are measured on the instrumental when a vocal stem exists
    yi = y - voc if voc is not None else y
    mid, side = yi.mean(axis=0), (yi[0] - yi[1]) / 2

    # spectra at 100 fps
    Sm = np.abs(librosa.stft(mid, n_fft=NFFT, hop_length=HOP)).astype(np.float32)
    Ss = np.abs(librosa.stft(side, n_fft=NFFT, hop_length=HOP)).astype(np.float32)
    freqs = librosa.fft_frequencies(sr=SR, n_fft=NFFT)
    H, P = librosa.decompose.hpss(Sm, margin=2.0)
    nF = Sm.shape[1]
    tF = np.arange(nF) / FR
    print("spectra + HPSS done")

    # loudness
    mom, st, integ, lra = loudness_curves(y)
    mom, st = mom[:nF], st[:nF]
    if len(mom) < nF:
        mom = np.pad(mom, (0, nF - len(mom)), mode="edge")
        st = np.pad(st, (0, nF - len(st)), mode="edge")

    # drums
    # drums: onsets as dB rises in bands of the percussive layer
    kick_env = rise(band_db(Sm, freqs, 35, 120))
    snare_env = np.sqrt(rise(band_db(P, freqs, 160, 320)) * rise(band_db(P, freqs, 1500, 5000)))
    hf_lvl = band_db(Sm + Ss, freqs, 6000, 16000)
    hf_env = rise(hf_lvl)
    hat_lvl = band_db(P, freqs, 7000, 16000)
    k_idx = pick(kick_env, 0.09, 7.0)
    s_idx = pick(snare_env, 0.1, 5.0)
    k_str = np.clip(kick_env[k_idx] / 18, 0, 1)
    s_str = np.clip(snare_env[s_idx] / 14, 0, 1)
    # crashes: a big HF rise whose level then stays up for ~400 ms
    crash = []
    for ix in pick(hf_env, 0.3, 5.0):
        pre = hf_lvl[max(0, ix - 30):max(1, ix - 4)].mean()
        post = hf_lvl[ix + 4:ix + 40].mean() if ix + 40 < nF else hf_lvl[ix:].mean()
        if post - pre > 4.0:
            crash.append((ix, float(np.clip((post - pre) / 12, 0, 1)), post - pre))

    # beat grid from the drum onsets
    onset_env = librosa.onset.onset_strength(S=librosa.amplitude_to_db(Sm, ref=np.max), sr=SR, hop_length=HOP)
    t_on = np.r_[refine(kick_env, k_idx), refine(snare_env, s_idx)]
    w_on = np.r_[kick_env[k_idx], snare_env[s_idx]]
    grid = beat_grid(onset_env, t_on, w_on, dur)
    per = grid["period"]
    # on-beat vs off-beat: the snare (backbeat) sits on beats
    rs, ph_s = phase_coherence(refine(snare_env, s_idx), snare_env[s_idx], per)
    rk, ph_k = phase_coherence(refine(kick_env, k_idx), kick_env[k_idx], per)
    ref_ph = ph_s if rs >= rk else ph_k
    cands = [grid["offset8"], grid["offset8"] + per / 2]
    off = min(cands, key=lambda c: abs(((c - ref_ph + per / 2) % per) - per / 2)) % per
    if grid["constant_tempo"]:
        beats = np.arange(off, dur, per)
    else:
        _, fr = librosa.beat.beat_track(onset_envelope=onset_env, sr=SR, hop_length=HOP, bpm=grid["bpm"], units="frames")
        beats = librosa.frames_to_time(fr, sr=SR, hop_length=HOP)
    grid["offset"], grid["beats"] = float(off), beats
    nb = len(beats)
    near = lambda tt: np.min(np.abs(beats[:, None] - tt[None, :]), axis=0) if len(tt) else np.array([])
    k_t, s_t = refine(kick_env, k_idx), refine(snare_env, s_idx)
    s_on = float(np.mean(near(s_t) < 0.045)) if len(s_idx) else 0
    k_on = float(np.mean(np.minimum(near(k_t), np.abs(near(k_t) - per / 2)) < 0.045)) if len(k_idx) else 0
    grid["snare_on_beat"], grid["kick_on_8th"] = round(s_on, 3), round(k_on, 3)
    print(f"drums: {len(k_idx)} kicks ({k_on:.0%} on the 8th grid), {len(s_idx)} snares ({s_on:.0%} on beats), {len(crash)} crashes")
    print(f"grid: {grid['bpm']} bpm, coherence {grid['coherence']}, constant={grid['constant_tempo']}, "
          f"local deviation rms {grid['fit_residual_ms']} ms")

    # tonal (22 kHz harmonic)
    y22 = librosa.resample(mid, orig_sr=SR, target_sr=SR_V)
    yh = librosa.effects.harmonic(y22, margin=3.0)
    chroma = librosa.feature.chroma_cqt(y=yh, sr=SR_V, hop_length=HOP_V, bins_per_octave=36)
    bf_v = np.clip(np.round(beats * SR_V / HOP_V).astype(int), 0, chroma.shape[1] - 1)
    chroma_b = librosa.util.sync(chroma, bf_v, aggregate=np.median)[:, :nb]
    if chroma_b.shape[1] < nb:
        chroma_b = np.pad(chroma_b, ((0, 0), (0, nb - chroma_b.shape[1])), mode="edge")
    cc = np.r_[0, np.linalg.norm(np.diff(chroma_b / (chroma_b.sum(0, keepdims=True) + 1e-9), axis=1), axis=0)]
    downs, glob_phase = downbeat_phase(beats, kick_env, snare_env, cc)
    print(f"bars: {len(downs)} (global phase {glob_phase})")

    key = key_estimate(chroma.mean(axis=1))
    bfF = np.clip(np.round(beats * FR).astype(int), 0, nF - 1)
    energy_b = np.array([mom[bfF[i]:bfF[i + 1] if i + 1 < nb else nF].mean() for i in range(nb)])
    chord_b, chord_conf = chords_per_beat(chroma_b, energy_b)

    # instruments (dB levels at 100 fps)
    dist_idx = band_db(Ss, freqs, 2500, 6000) - band_db(Ss, freqs, 250, 1000)
    side_lvl = band_db(Ss, freqs, 250, 5000)
    w_g = 1 / (1 + np.exp(-(dist_idx + 14) / 3))
    inst_db = {
        "kick": band_db(P, freqs, 35, 120),
        "snare": band_db(P, freqs, 1500, 5000),
        "cymbals": hf_lvl,
        "bass": band_db(H, freqs, 35, 180),
        "guitars": side_lvl + 10 * np.log10(np.maximum(w_g, 1e-3)),
        "strings_synth": band_db(H, freqs, 250, 2500) + 10 * np.log10(np.maximum(1 - w_g, 1e-3)) - 3,
    }
    stem = voc is not None
    if cache and Path(cache).exists() and bool(np.load(cache)["stem"]) == stem:
        C = np.load(cache)
        tv, ev, f0, vprob, vflux = C["tv"], C["ev"], C["f0"], C["vprob"], C["vflux"]
    else:
        tv, ev, f0, vprob, vflux = vocal_from_stem(voc) if stem else vocal_pipeline(y)[:5]
        if cache:
            np.savez(cache, tv=tv, ev=ev, f0=f0, vprob=vprob, vflux=vflux, stem=stem)
    phrases, vscore = vocal_phrases(tv, ev, f0, vprob, vflux, dur, stem=stem)
    notes = melody_notes(tv, f0)
    inst_db["vocals"] = np.interp(tF, tv, ev)
    vscoreF = np.interp(tF, tv, vscore)
    print(f"vocals: {len(phrases)} phrases, {len(notes)} notes")

    # bars
    bar_starts = [float(beats[i]) for i in downs]
    bars = []
    for bi, d in enumerate(downs):
        a = float(beats[d])
        b = float(beats[downs[bi + 1]]) if bi + 1 < len(downs) else min(dur, a + 4 * grid["period"])
        fa, fb = frames_of(a), max(frames_of(a) + 1, frames_of(b))
        bars.append({"i": bi, "start": round(a, 4), "end": round(b, 4), "beat": int(d),
                     "lufs": round(float(mom[fa:fb].mean()), 2), "fa": fa, "fb": fb})
    blufs = np.array([b["lufs"] for b in bars])
    q = np.percentile(blufs[blufs > -60], [20, 55, 85]) if np.any(blufs > -60) else [-40, -20, -10]
    for b in bars:
        L = b["lufs"]
        b["dynamics"] = "quiet" if L < q[0] else "medium" if L < q[1] else "loud" if L < q[2] else "peak"
        fa, fb = b.pop("fa"), b.pop("fb")
        pres = {}
        for k, v in inst_db.items():
            pres[k] = round(float(norm01(v[fa:fb].mean(), 5, 98, ref=v)), 3)
        pres["vocals"] = round(float(np.mean(vscoreF[fa:fb] > 0.45)), 3)
        b["presence"] = pres
        b["kicks"] = int(np.sum((k_idx >= fa) & (k_idx < fb)))
        b["snares"] = int(np.sum((s_idx >= fa) & (s_idx < fb)))
        b["crash"] = any(fa - 3 <= c[0] < fb for c in crash)
        b["hat_density"] = round(float(norm01(hat_lvl[fa:fb].mean(), 5, 98, ref=hat_lvl)), 3)
        b["chords"] = [chord_b[i] for i in range(b["beat"], min(nb, b["beat"] + 4))]

    # structure on beat-synchronous features
    mel = librosa.feature.melspectrogram(S=Sm ** 2, sr=SR, n_mels=64)
    mfcc = librosa.feature.mfcc(S=librosa.power_to_db(mel), n_mfcc=13)
    mfcc_b = librosa.util.sync(mfcc, bfF, aggregate=np.mean)[:, :nb]
    if mfcc_b.shape[1] < nb:
        mfcc_b = np.pad(mfcc_b, ((0, 0), (0, nb - mfcc_b.shape[1])), mode="edge")
    loud_b = energy_b[None, :]
    vox_b = np.array([vscoreF[bfF[i]:bfF[min(i + 1, nb - 1)] + 1].mean() for i in range(nb)])[None, :]
    feats = np.vstack([chroma_b * 2, mfcc_b[1:] / 20, loud_b / 6, vox_b * 2])
    bounds, novelty, _ = segment(feats, downs, nb)
    labels = label_sections(bounds, feats)
    sections = []
    for i in range(len(bounds) - 1):
        a_b, b_b = bounds[i], bounds[i + 1]
        a = float(beats[a_b])
        b = float(beats[b_b]) if b_b < nb else dur
        fa, fb = frames_of(a), frames_of(b)
        sections.append({"label": labels[i], "start": round(a, 3), "end": round(b, 3),
                         "bars": round((b_b - a_b) / 4, 2), "loudness_lufs": round(float(mom[fa:fb].mean()), 2),
                         "vocals": round(float(np.mean(vscoreF[fa:fb] > 0.45)), 3),
                         "chords": " ".join(dict.fromkeys(chord_b[a_b:b_b]))})
    name_sections(sections)

    # events
    events = []
    for s in sections[1:]:
        events.append({"t": s["start"], "type": "section", "label": f"{s['label']} {s['name']}"})
    # impacts and dropouts: bar-to-bar jumps in loudness or in how much of the band is playing
    def band(b):
        return (b["presence"]["guitars"] + b["presence"]["bass"] + b["hat_density"]) / 3

    for i in range(1, len(bars)):
        if bars[i]["lufs"] < -40:
            continue
        jump = bars[i]["lufs"] - bars[i - 1]["lufs"]
        dband = band(bars[i]) - band(bars[i - 1])
        if jump > 2.5 or dband > 0.2 or (bars[i]["crash"] and jump > 1.0):
            events.append({"t": bars[i]["start"], "type": "impact", "label": f"{jump:+.1f} LU, band {dband:+.2f}",
                           "strength": round(float(max(jump / 4, dband / 0.3)), 2)})
        elif jump < -2.5 or dband < -0.2:
            events.append({"t": bars[i]["start"], "type": "dropout", "end": bars[i]["end"],
                           "label": f"{jump:+.1f} LU, band {dband:+.2f}"})
    # builds: >=2 bars of rising short-term loudness / hats leading into an impact
    imp = [e for e in events if e["type"] == "impact"]
    for e in imp:
        bi = next(i for i, b in enumerate(bars) if abs(b["start"] - e["t"]) < 1e-3)
        j = bi
        while j - 1 >= 0 and bi - j < 8 and (bars[j - 1]["lufs"] <= bars[j]["lufs"] + 0.4 or
                                              bars[j - 1]["hat_density"] < bars[j]["hat_density"]):
            j -= 1
        if bi - j >= 2 and not any(x["type"] == "build" and abs(x["t"] - bars[j]["start"]) < 1e-3 for x in events):
            events.append({"t": bars[j]["start"], "type": "build", "end": e["t"], "label": f"{bi - j} bars"})
    # stops: momentary loudness falls 10 dB under the 2 s median for 0.12..1.2 s
    med = ndimage.median_filter(mom, size=int(2 * FR), mode="nearest")
    lowm = mom < med - 10
    lab, n = ndimage.label(lowm)
    for k in range(1, n + 1):
        idx = np.where(lab == k)[0]
        d = len(idx) / FR
        if 0.12 <= d <= 1.2 and mom[idx].mean() < integ - 6:
            events.append({"t": round(idx[0] / FR, 3), "type": "stop", "end": round(idx[-1] / FR, 3), "label": f"{d:.2f}s"})
    for c in crash:
        events.append({"t": round(c[0] / FR - ONSET_LAT, 3), "type": "crash", "strength": round(float(c[1]), 3)})
    vr = np.array([n["midi"] for n in notes]) if notes else np.array([0])
    top = np.percentile(vr, 85)
    for n_ in notes:
        if n_["end"] - n_["start"] >= 0.6 and n_["midi"] >= top:
            events.append({"t": n_["start"], "type": "held_note", "end": n_["end"], "label": n_["name"]})
    events.sort(key=lambda e: e["t"])

    lyrics = None
    if lyrics_path:
        lines = [x.strip() for x in Path(lyrics_path).read_text().splitlines() if x.strip()]
        ph = [p for p in phrases if start <= p["start"] < end]
        lyrics = align_lyrics(lines, ph)

    analysis = {
        "meta": {"file": Path(path).name, "duration": round(dur, 3), "sr": SR, "frame_rate": FR,
                 "excerpt": {"start": start, "end": end}},
        "tempo": {"bpm": grid["bpm"], "period": round(grid["period"], 6), "offset": round(grid["offset"], 5),
                  "constant_tempo": grid["constant_tempo"], "fit_residual_ms": grid["fit_residual_ms"],
                  "coherence": grid["coherence"], "local_dev_ms": grid["local_dev_ms"],
                  "snare_on_beat": grid["snare_on_beat"], "kick_on_8th": grid["kick_on_8th"], "beats": [round(float(b), 4) for b in beats],
                  "downbeats": [round(float(beats[i]), 4) for i in downs], "time_signature": "4/4 (assumed, phase checked locally)"},
        "key": key,
        "chords": compress_chords(beats, chord_b, chord_conf, key, dur),
        "loudness": {"integrated_lufs": round(integ, 2), "lra_lu": round(lra, 2),
                     "momentary_10hz": [round(float(x), 1) for x in mom[::10]],
                     "short_term_10hz": [round(float(x), 1) for x in st[::10]],
                     "bar_thresholds_lufs": [round(float(x), 2) for x in q]},
        "bars": bars,
        "sections": sections,
        "drums": {"kick": [{"t": round(float(tt), 3), "s": round(float(s), 3)} for tt, s in zip(k_t, k_str)],
                  "snare": [{"t": round(float(tt), 3), "s": round(float(s), 3)} for tt, s in zip(s_t, s_str)],
                  "crash": [{"t": round(c[0] / FR - ONSET_LAT, 3), "s": round(float(c[1]), 3)} for c in crash]},
        "vocals": {"phrases": phrases, "lines": group_lines(phrases), "notes": notes,
                   "range": [notes and min(n["name"] for n in notes), None],
                   "source": "separated stem (MDX-Net)" if stem else "DSP centre/foreground estimate",
                   "note": "vocal timing, pitch and intensity only; words are not transcribed"},
        "events": events,
        "novelty": [round(float(x), 3) for x in novelty],
    }
    if notes:
        mn = min(notes, key=lambda n: n["midi"])
        mx = max(notes, key=lambda n: n["midi"])
        analysis["vocals"]["range"] = [mn["name"], mx["name"]]
    if lyrics is not None:
        analysis["lyrics_alignment"] = lyrics

    # per-frame data the cues are built from (kept out of the json)
    lanes = {
        "tF": tF, "mom": mom, "st": st, "inst_db": inst_db, "vscoreF": vscoreF, "tv": tv, "f0": f0,
        "kick": (k_t, k_str), "snare": (s_t, s_str), "crash": (np.array([c[0] for c in crash]) / FR - ONSET_LAT,
                                                                             np.array([c[1] for c in crash])),
        "centroid": librosa.feature.spectral_centroid(S=Sm, sr=SR)[0],
    }
    return analysis, lanes, y


def compress_chords(beats, lab, conf, key, dur):
    out = []
    for i, c in enumerate(lab):
        t = float(beats[i])
        if out and out[-1]["chord"] == c:
            out[-1]["end"] = round(float(beats[i + 1]) if i + 1 < len(beats) else dur, 3)
            out[-1]["_c"].append(conf[i])
        else:
            out.append({"chord": c, "roman": roman(c, key), "start": round(t, 3),
                        "end": round(float(beats[i + 1]) if i + 1 < len(beats) else dur, 3), "_c": [conf[i]]})
    for o in out:
        o["confidence"] = round(float(np.mean(o.pop("_c"))), 3)
    return out


# ------------------------------------------------------------------ excerpt, cues, beats.json

def shift(obj, t0, t1):
    """Copy of the song-wide analysis cut to [t0, t1) with times relative to t0."""
    def rel(x):
        return round(x - t0, 4)

    def inside(a, b=None):
        b = a if b is None else b
        return b > t0 and a < t1

    A = obj
    ex = {"meta": dict(A["meta"]), "key": A["key"]}
    ex["meta"]["duration"] = round(t1 - t0, 3)
    T = A["tempo"]
    ex["tempo"] = {k: T[k] for k in ("bpm", "period", "constant_tempo", "fit_residual_ms", "time_signature")}
    ex["tempo"]["beats"] = [rel(b) for b in T["beats"] if t0 - 1e-6 <= b < t1]
    ex["tempo"]["downbeats"] = [rel(b) for b in T["downbeats"] if t0 - 1e-6 <= b < t1]
    ex["tempo"]["offset"] = round((T["offset"] - t0) % T["period"], 5)
    ex["chords"] = [dict(c, start=rel(max(c["start"], t0)), end=rel(min(c["end"], t1))) for c in A["chords"] if inside(c["start"], c["end"])]
    ex["bars"] = [dict(b, start=rel(b["start"]), end=rel(b["end"])) for b in A["bars"] if inside(b["start"], b["end"])]
    ex["sections"] = [dict(s, start=rel(max(s["start"], t0)), end=rel(min(s["end"], t1)), cut=s["start"] < t0)
                      for s in A["sections"] if inside(s["start"], s["end"])]
    ex["drums"] = {k: [dict(h, t=rel(h["t"])) for h in v if t0 <= h["t"] < t1] for k, v in A["drums"].items()}
    ex["vocals"] = {
        "phrases": [dict(p, start=rel(p["start"]), end=rel(p["end"]), syllable_onsets=[rel(x) for x in p["syllable_onsets"]])
                    for p in A["vocals"]["phrases"] if inside(p["start"], p["end"])],
        "lines": [dict(l, start=rel(l["start"]), end=rel(l["end"])) for l in A["vocals"]["lines"] if inside(l["start"], l["end"])],
        "notes": [dict(n, start=rel(n["start"]), end=rel(n["end"])) for n in A["vocals"]["notes"] if inside(n["start"], n["end"])],
        "range": A["vocals"]["range"], "note": A["vocals"]["note"]}
    ex["events"] = [dict(e, t=rel(e["t"]), **({"end": rel(e["end"])} if "end" in e else {}))
                    for e in A["events"] if inside(e["t"], e.get("end"))]
    ex["loudness"] = {"integrated_lufs_song": A["loudness"]["integrated_lufs"],
                      "momentary_10hz": A["loudness"]["momentary_10hz"][int(t0 * 10):int(t1 * 10)],
                      "short_term_10hz": A["loudness"]["short_term_10hz"][int(t0 * 10):int(t1 * 10)]}
    if "lyrics_alignment" in A:
        ex["lyrics_alignment"] = [dict(l, start=rel(l["start"]), end=rel(l["end"])) for l in A["lyrics_alignment"]]
    return ex


def build_cues(lanes, t0, t1, fps):
    n = int(math.ceil((t1 - t0) * fps))
    t = t0 + np.arange(n) / fps
    tF = lanes["tF"]

    def at(x):
        return np.interp(t, tF, x)

    def impulses(times, strengths, tau, attack=0.012):
        out = np.zeros(n)
        for tt, s in zip(times, strengths):
            if tt < t0 - 3 * tau or tt > t1:
                continue
            d = t - tt
            env = np.where(d < 0, np.exp(d / attack) * (d > -4 * attack), np.exp(-np.maximum(d, 0) / tau))
            out = np.maximum(out, min(1.0, s * 1.15) * env)
        return out

    mom, st = lanes["mom"], lanes["st"]
    cues = {
        "fps": fps, "start": t0, "frames": n,
        "loud": norm01(at(mom), 5, 99.5, ref=mom),
        "loud_st": norm01(at(st), 5, 99.5, ref=st),
        "kick": impulses(*lanes["kick"], tau=0.11),
        "snare": impulses(*lanes["snare"], tau=0.13),
        "crash": impulses(*lanes["crash"], tau=0.7),
        "bright": norm01(at(smooth(lanes["centroid"], 8)), 5, 98, ref=lanes["centroid"]),
        "vocal": np.clip(at(smooth(lanes["vscoreF"], 6)), 0, 1),
    }
    for k in ("bass", "guitars", "strings_synth", "cymbals"):
        v = lanes["inst_db"][k]
        cues[k] = norm01(at(smooth(v, 10)), 5, 98, ref=v)
    f0 = lanes["f0"]
    midi = librosa.hz_to_midi(f0)
    ok = np.isfinite(midi)
    lo, hi = (np.percentile(midi[ok], 3), np.percentile(midi[ok], 98)) if ok.any() else (40, 80)
    pm = np.interp(t, lanes["tv"], np.where(ok, (midi - lo) / (hi - lo + 1e-9), -1))
    cues["pitch"] = np.where(pm < 0, -1, np.clip(pm, 0, 1))
    out = {}
    for k, v in cues.items():
        out[k] = [round(float(x), 3) for x in v] if isinstance(v, np.ndarray) else v
    out["lanes"] = [k for k in out if isinstance(out[k], list)]
    return out


def motion_reel_beats(analysis, t0, t1):
    T = analysis["tempo"]
    beats = [round(b - t0, 5) for b in T["beats"] if b >= t0 - T["period"] * 0.5 and b < t1]
    downs = [round(b - t0, 5) for b in T["downbeats"] if b >= t0 - T["period"] * 0.5 and b < t1]
    # grid anchored on the first downbeat so beat u=0 is a bar line
    off = downs[0] if downs else beats[0]
    period = T["period"]
    n0 = int(math.floor(-off / period))
    grid_beats = [round(off + period * k, 5) for k in range(n0, int((t1 - t0 - off) / period) + 1)]
    bars = analysis_bars_rel(analysis, t0, t1)
    return {"bpm": T["bpm"], "period": period, "offset": off, "beats": [b for b in grid_beats if b >= 0],
            "downbeats": downs, "sections": [], "bar_energy": [b["lufs"] for b in bars],
            "duration": round(t1 - t0, 3), "fit_residual_ms": T["fit_residual_ms"],
            "source": f"{analysis['meta']['file']} from {t0:.3f}s, measured by tools/song-analyzer"}


def analysis_bars_rel(A, t0, t1):
    return [b for b in A["bars"] if b["end"] > t0 and b["start"] < t1]


# ------------------------------------------------------------------ report

def write_report(out_dir, analysis, excerpt, audio_src):
    tpl = (Path(__file__).parent / "report_template.html").read_text()
    slim = dict(analysis)
    html = tpl.replace("/*__DATA__*/null", json.dumps(clean(slim), separators=(",", ":"), allow_nan=False)) \
              .replace("__AUDIO__", audio_src or "")
    (out_dir / "report.html").write_text(html)


def summary(A, t0, t1):
    T, K, Lo = A["tempo"], A["key"], A["loudness"]
    print("\n=== SUMMARY ===")
    print(f"tempo {T['bpm']} bpm ({'constant' if T['constant_tempo'] else 'variable'}, fit {T['fit_residual_ms']} ms), "
          f"key {K['name']} (r={K['confidence']}, next {K['runner_up']}), integrated {Lo['integrated_lufs']} LUFS, LRA {Lo['lra_lu']} LU")
    print("sections:")
    for s in A["sections"]:
        mark = " <" if s["end"] > t0 and s["start"] < t1 else ""
        print(f"  {mmss(s['start'])}-{mmss(s['end'])}  {s['label']} {s['name']:<22} {s['bars']:>5} bars  "
              f"{s['loudness_lufs']:6.1f} LUFS  vox {s['vocals']:.2f}  {s['chords'][:60]}{mark}")
    print(f"excerpt {mmss(t0)}-{mmss(t1)}: bars")
    for b in A["bars"]:
        if b["end"] > t0 and b["start"] < t1:
            p = b["presence"]
            print(f"  bar {b['i']:3d} {mmss(b['start'])} {b['dynamics']:<6} {b['lufs']:6.1f}  K{b['kicks']:2d} S{b['snares']:2d} "
                  f"{'CR' if b['crash'] else '  '} hat {b['hat_density']:.2f} bass {p['bass']:.2f} gtr {p['guitars']:.2f} "
                  f"str {p['strings_synth']:.2f} vox {p['vocals']:.2f}  {' '.join(b['chords'])}")
    L = [l for l in A["vocals"]["lines"] if l["end"] > t0 and l["start"] < t1]
    print(f"vocal lines in excerpt: {len(L)}  (phrases: {sum(1 for p in A['vocals']['phrases'] if p['end'] > t0 and p['start'] < t1)})")
    for l in L:
        print(f"  {mmss(l['start'])}-{mmss(l['end'])}  {l['dur']:5.2f}s  ~{l['syllables_est']:2d} syl  peak {l['peak_level']:.2f}  top {l['midi_max']}")
    print("events in excerpt:")
    for e in A["events"]:
        if t0 <= e["t"] < t1 and e["type"] != "crash":
            print(f"  {mmss(e['t'])} {e['type']:<10} {e.get('label', '')}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("song")
    ap.add_argument("--out", required=True)
    ap.add_argument("--start", default="0")
    ap.add_argument("--end", default=None)
    ap.add_argument("--snap-start", action="store_true", help="move --start to the nearest beat within 0.5 s")
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--excerpt-wav", default=None, help="write the decoded excerpt (sample-exact with the analysis)")
    ap.add_argument("--lyrics", default=None, help="your own lyric sheet, one sung line per line, to align to phrases")
    ap.add_argument("--vocal-model", default=None, help="MDX-Net ONNX vocal model (e.g. UVR-MDX-NET-Voc_FT.onnx); "
                    "without it vocals are estimated with DSP only")
    ap.add_argument("--stems", default=None, help="write vocals.wav + instrumental.wav here (needs --vocal-model)")
    ap.add_argument("--cache", action="store_true", help="cache the (slow) vocal extraction in --out")
    ap.add_argument("--audio-src", default=None, help="audio URL/path the report should play (relative to report.html)")
    a = ap.parse_args()

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    t0 = parse_time(a.start)
    A, lanes, y = analyze(a.song, t0, 1e9, a.fps, cache=out / ".vocal_cache.npz" if a.cache else None,
                          vocal_model=a.vocal_model, stems_dir=a.stems)
    dur = A["meta"]["duration"]
    t1 = min(parse_time(a.end) or dur, dur)
    if a.snap_start:
        bts = np.array(A["tempo"]["beats"])
        near = bts[np.argmin(np.abs(bts - t0))]
        if abs(near - t0) <= 0.5:
            print(f"start snapped {t0:.3f} -> {near:.3f} (nearest beat)")
            t0 = float(near)
    A["meta"]["excerpt"] = {"start": round(t0, 4), "end": round(t1, 4)}
    if a.lyrics:
        lines = [x.strip() for x in Path(a.lyrics).read_text().splitlines() if x.strip()]
        A["lyrics_alignment"] = align_lyrics(lines, [p for p in A["vocals"]["phrases"] if t0 <= p["start"] < t1])

    ex = shift(A, t0, t1)
    cues = build_cues(lanes, t0, t1, a.fps)
    (out / "analysis.json").write_text(json.dumps(clean(A), indent=1, allow_nan=False))
    (out / "excerpt.json").write_text(json.dumps(clean(ex), indent=1, allow_nan=False))
    (out / "cues.json").write_text(json.dumps(clean(cues), separators=(",", ":"), allow_nan=False))
    (out / "beats.json").write_text(json.dumps(clean(motion_reel_beats(A, t0, t1)), indent=1, allow_nan=False))
    write_report(out, A, ex, a.audio_src)
    if a.excerpt_wav:
        seg = y[:, int(round(t0 * SR)):int(round(t1 * SR))].copy()
        fo = int(0.03 * SR)
        seg[:, -fo:] *= np.linspace(1, 0, fo)
        sf.write(a.excerpt_wav, seg.T, SR, subtype="PCM_24")
        print(f"excerpt audio -> {a.excerpt_wav} ({seg.shape[1] / SR:.3f} s)")
    summary(A, t0, t1)
    print(f"\n-> {out}/analysis.json excerpt.json cues.json beats.json report.html")


if __name__ == "__main__":
    main()
