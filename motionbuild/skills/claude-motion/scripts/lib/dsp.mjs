// Tiny deterministic DSP kit (pure JS, Float32Array, 48 kHz): notes, filters,
// envelopes, oscillators, drum/tonal voices, Freeverb, buses, onset analysis.
// Every random source takes an explicit seeded rng.
import { SR, mulberry32 } from './common.mjs';
export { SR, mulberry32 };

export const TAU = Math.PI * 2;
export const sec = (s) => Math.max(0, Math.round(s * SR));
export const dbToGain = (db) => 10 ** (db / 20);

// ------------------------------------------------------------------ notes ---
const NAMES = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
export function midi(n) {
  if (typeof n === 'number') return n;
  const m = /^([A-G])([#b]?)(-?\d+)$/.exec(n);
  if (!m) throw new Error(`bad note ${n}`);
  return 12 * (Number(m[3]) + 1) + NAMES[m[1]] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0);
}
export const mtof = (m) => 440 * 2 ** ((m - 69) / 12);
export const hz = (n) => (typeof n === 'number' && n > 127 ? n : mtof(midi(n)));

// ---------------------------------------------------------------- filters ---
// RBJ biquad; coefficients may be updated per block for sweeps.
export class Biquad {
  constructor(type, f, q = 0.707, gainDb = 0) { this.z1 = 0; this.z2 = 0; this.set(type, f, q, gainDb); }
  set(type, f, q = 0.707, gainDb = 0) {
    f = Math.min(Math.max(f, 10), SR * 0.49);
    const w = TAU * f / SR, c = Math.cos(w), s = Math.sin(w), al = s / (2 * q), A = 10 ** (gainDb / 40);
    let b0, b1, b2, a0, a1, a2;
    if (type === 'lp') { b0 = (1 - c) / 2; b1 = 1 - c; b2 = b0; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al; }
    else if (type === 'hp') { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = b0; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al; }
    else if (type === 'bp') { b0 = al; b1 = 0; b2 = -al; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al; }
    else if (type === 'peak') { b0 = 1 + al * A; b1 = -2 * c; b2 = 1 - al * A; a0 = 1 + al / A; a1 = -2 * c; a2 = 1 - al / A; }
    else throw new Error(`filter ${type}`);
    this.b0 = b0 / a0; this.b1 = b1 / a0; this.b2 = b2 / a0; this.a1 = a1 / a0; this.a2 = a2 / a0;
    return this;
  }
  tick(x) { // transposed direct form II
    const y = this.b0 * x + this.z1;
    this.z1 = this.b1 * x - this.a1 * y + this.z2;
    this.z2 = this.b2 * x - this.a2 * y;
    return y;
  }
}
export function filt(x, type, f, q = 0.707, gainDb = 0) {
  const b = new Biquad(type, f, q, gainDb), y = new Float32Array(x.length);
  for (let i = 0; i < x.length; i++) y[i] = b.tick(x[i]);
  return y;
}
// Time-varying cutoff: fc(i/len) -> Hz, recomputed every 32 samples.
export function sweep(x, type, fc, q = 0.707) {
  const b = new Biquad(type, fc(0), q), y = new Float32Array(x.length);
  for (let i = 0; i < x.length; i++) {
    if ((i & 31) === 0) b.set(type, fc(i / x.length), q);
    y[i] = b.tick(x[i]);
  }
  return y;
}

// -------------------------------------------------------------- envelopes ---
export const expDecay = (n, tau) => { const e = new Float32Array(n); for (let i = 0; i < n; i++) e[i] = Math.exp(-i / SR / tau); return e; };
export function adsr(n, a = 0.005, d = 0.1, s = 0.7, r = 0.1) {
  const e = new Float32Array(n), A = sec(a), D = sec(d), R = Math.min(sec(r), n);
  for (let i = 0; i < n; i++) {
    let v = i < A ? i / A : s + (1 - s) * Math.exp(-(i - A) / Math.max(1, D) * 3);
    if (i > n - R) v *= (n - i) / R;
    e[i] = v;
  }
  return e;
}
export function mul(x, e) { for (let i = 0; i < x.length; i++) x[i] *= e[i] ?? 0; return x; }
export function gain(x, g) { for (let i = 0; i < x.length; i++) x[i] *= g; return x; }
export function add(dst, src, at = 0, g = 1) { for (let i = 0; i < src.length; i++) { const j = i + at; if (j >= 0 && j < dst.length) dst[j] += src[i] * g; } return dst; }
export function sat(x, drive = 1.5) { const k = Math.tanh(drive); for (let i = 0; i < x.length; i++) x[i] = Math.tanh(x[i] * drive) / k; return x; }
export function fadeIn(x, s) { const n = Math.min(sec(s), x.length); for (let i = 0; i < n; i++) x[i] *= i / n; return x; }
export function fadeOut(x, s, pow = 2) { const n = Math.min(sec(s), x.length); for (let i = 0; i < n; i++) x[x.length - 1 - i] *= (i / n) ** pow; return x; }
export const reverse = (x) => Float32Array.from(x).reverse();

// ------------------------------------------------------------ oscillators ---
// osc(n, freq(tSec) | Hz, shape) with phase accumulation; PolyBLEP saw/square.
const blep = (t, dt) => { if (t < dt) { t /= dt; return t + t - t * t - 1; } if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; } return 0; };
export function osc(n, freq, shape = 'sine', phase0 = 0) {
  const y = new Float32Array(n), f = typeof freq === 'function' ? freq : () => freq;
  let ph = phase0;
  for (let i = 0; i < n; i++) {
    const dt = f(i / SR) / SR;
    if (shape === 'sine') y[i] = Math.sin(TAU * ph);
    else if (shape === 'saw') y[i] = 2 * ph - 1 - blep(ph, dt);
    else if (shape === 'square') y[i] = (ph < 0.5 ? 1 : -1) + blep(ph, dt) - blep((ph + 0.5) % 1, dt);
    else if (shape === 'tri') y[i] = 1 - 4 * Math.abs(ph - 0.5);
    ph += dt; ph -= Math.floor(ph);
  }
  return y;
}
export function noise(n, rng) { const y = new Float32Array(n); for (let i = 0; i < n; i++) y[i] = rng() * 2 - 1; return y; }

// ----------------------------------------------------------------- drums ---
export function kick(rng, { soft = false, pitch = 48, len = 0.42 } = {}) {
  const n = sec(len);
  const body = osc(n, (t) => pitch + 120 * Math.exp(-t / 0.03) + 26 * Math.exp(-t / 0.12));
  mul(body, expDecay(n, soft ? 0.16 : 0.22));
  const click = filt(noise(sec(0.01), rng), 'hp', 2500);
  mul(click, expDecay(click.length, 0.002));
  add(body, click, 0, soft ? 0.15 : 0.5);
  sat(body, soft ? 1.1 : 1.8);
  return soft ? filt(body, 'lp', 300) : body;
}
export function clap(rng, { len = 0.35 } = {}) {
  const n = sec(len), y = new Float32Array(n);
  for (const [off, g] of [[0, 0.8], [0.009, 0.7], [0.019, 0.9]]) {
    const b = noise(sec(0.012), rng); mul(b, expDecay(b.length, 0.004)); add(y, b, sec(off), g);
  }
  const tail = noise(n, rng); mul(tail, expDecay(n, 0.07)); add(y, tail, sec(0.02), 0.6);
  const out = filt(filt(y, 'hp', 900), 'lp', 4200);
  add(out, mul(osc(sec(0.05), 200), expDecay(sec(0.05), 0.015)), 0, 0.25);
  return out;
}
export function hat(rng, { open = false } = {}) {
  const n = sec(open ? 0.35 : 0.06);
  let y = noise(n, rng);
  for (const f of [3150, 4720, 6890, 8430]) add(y, osc(n, f, 'square'), 0, 0.15);
  y = filt(filt(y, 'hp', 7000), 'peak', 10000, 1, 4);
  return mul(y, expDecay(n, open ? 0.12 : 0.015));
}
export function crash(rng, { len = 2.2 } = {}) {
  const n = sec(len);
  let y = filt(noise(n, rng), 'hp', 4000);
  for (const f of [3970, 5140, 6230, 7710, 9230, 11300]) add(y, mul(osc(n, f), osc(n, f * 1.41)), 0, 0.08);
  y = filt(y, 'hp', 3000);
  return mul(y, expDecay(n, len * 0.32));
}
export function shaker(rng) { const n = sec(0.08), y = filt(noise(n, rng), 'bp', 7000, 1.2); return mul(y, adsr(n, 0.015, 0.03, 0, 0.04)); }
export function rim(rng) { const n = sec(0.06), y = osc(n, 1700); add(y, osc(n, 820), 0, 0.6); add(y, filt(noise(n, rng), 'bp', 3000, 3), 0, 0.3); return mul(y, expDecay(n, 0.012)); }

// ----------------------------------------------------------------- tonal ---
export function bass(note, len, { cutoff = 900, drive = 1.6 } = {}) {
  const f = hz(note), n = sec(len);
  const y = osc(n, f, 'saw'); add(y, osc(n, f, 'sine'), 0, 0.8);
  const env = adsr(n, 0.004, 0.12, 0.7, 0.04);
  const out = sweep(y, 'lp', (p) => 120 + cutoff * Math.exp(-p * len / 0.08), 1.1);
  return sat(mul(out, env), drive);
}
// Detuned supersaw pad, stereo. cutoff number or [start, end].
export function pad(notes, len, { cutoff = 2400, attack = 0.08, release = 0.3, voices = 5, detune = 0.12, rng } = {}) {
  const n = sec(len + release), L = new Float32Array(n), R = new Float32Array(n);
  const [c0, c1] = Array.isArray(cutoff) ? cutoff : [cutoff, cutoff];
  const r = rng ?? mulberry32(7);
  for (const note of notes) {
    const f = hz(note);
    for (let v = 0; v < voices; v++) {
      const d = (v / (voices - 1 || 1) - 0.5) * 2 * detune, pan = (v / (voices - 1 || 1)) * 2 - 1;
      const y = osc(n, f * 2 ** (d / 12), 'saw', r());
      add(L, y, 0, Math.cos((pan + 1) * Math.PI / 4) / voices);
      add(R, y, 0, Math.sin((pan + 1) * Math.PI / 4) / voices);
    }
  }
  const env = adsr(n, attack, 0.4, 0.85, release);
  const fc = (p) => c0 * (c1 / c0) ** p;
  return [mul(sweep(L, 'lp', fc, 0.8), env), mul(sweep(R, 'lp', fc, 0.8), env)];
}
export function pluck(note, len = 0.4, { bright = 4000 } = {}) {
  const f = hz(note), n = sec(len);
  const y = osc(n, f, 'saw'); add(y, osc(n, f * 2, 'square'), 0, 0.3);
  return mul(sweep(y, 'lp', (p) => 300 + bright * Math.exp(-p * len / 0.06), 1.4), adsr(n, 0.002, 0.15, 0.2, 0.08));
}
// Karplus-Strong string.
export function string(note, len, rng, { damp = 0.996, bright = 0.5 } = {}) {
  const f = hz(note), n = sec(len), N = Math.max(2, Math.round(SR / f)), buf = noise(N, rng), y = new Float32Array(n);
  let last = 0;
  for (let i = 0; i < n; i++) {
    const j = i % N, v = buf[j];
    y[i] = v;
    const nv = damp * (bright * v + (1 - bright) * last);
    last = v; buf[j] = nv * 0.5 + buf[(j + 1) % N] * 0.5 * damp;
  }
  return fadeOut(y, 0.02);
}
// FM electric piano.
export function keys(note, len) {
  const f = hz(note), n = sec(len), y = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR, I = 2.2 * Math.exp(-t / 0.25);
    y[i] = Math.sin(TAU * f * t + I * Math.sin(TAU * f * 14 * t) * 0.15 + I * Math.sin(TAU * f * t));
  }
  return mul(y, adsr(n, 0.003, 0.5, 0.3, 0.15));
}
export function bell(note, len = 1.2) {
  const f = hz(note), n = sec(len), y = new Float32Array(n);
  for (const [r, g, tau] of [[1, 1, 0.6], [2.76, 0.5, 0.35], [5.4, 0.3, 0.2], [8.93, 0.18, 0.1]]) add(y, mul(osc(n, f * r), expDecay(n, tau * len)), 0, g);
  return y;
}

// ----------------------------------------------------------- transitions ---
export function riser(rng, len = 2, { from = 300, to = 6000 } = {}) {
  const n = sec(len), y = sweep(noise(n, rng), 'bp', (p) => from * (to / from) ** (p ** 1.5), 2.5);
  for (let i = 0; i < n; i++) y[i] *= (i / n) ** 2.2;
  add(y, mul(osc(n, (t) => 110 * 2 ** (2 * t / len)), adsr(n, len * 0.8, 0.1, 1, 0.01)), 0, 0.12);
  return fadeOut(y, 0.004, 1);
}
export function whoosh(rng, len = 0.6, { from = 400, to = 3200, peak = 0.7 } = {}) {
  const n = sec(len), y = sweep(noise(n, rng), 'bp', (p) => from * (to / from) ** p, 1.8);
  for (let i = 0; i < n; i++) { const p = i / n; y[i] *= p < peak ? (p / peak) ** 2 : (1 - (p - peak) / (1 - peak)) ** 1.5; }
  return y;
}
export function subDrop(len = 1.2) { const n = sec(len); return mul(osc(n, (t) => 30 + 50 * Math.exp(-t / 0.25)), expDecay(n, len * 0.4)); }

// ---------------------------------------------------------------- reverb ---
// Freeverb (8 combs + 4 allpasses per channel), stereo out from mono in.
export function freeverb(x, { room = 0.82, damp = 0.3, wet = 1, tail = 2.5 } = {}) {
  const k = SR / 44100, n = x.length + sec(tail);
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617], aps = [556, 441, 341, 225];
  const out = [new Float32Array(n), new Float32Array(n)];
  for (let ch = 0; ch < 2; ch++) {
    const spread = ch ? 23 : 0, y = out[ch];
    const cb = combs.map((d) => ({ b: new Float32Array(Math.round((d + spread) * k)), i: 0, s: 0 }));
    const ab = aps.map((d) => ({ b: new Float32Array(Math.round((d + spread) * k)), i: 0 }));
    for (let i = 0; i < n; i++) {
      const inp = (i < x.length ? x[i] : 0) * 0.015;
      let acc = 0;
      for (const c of cb) {
        const o = c.b[c.i]; c.s = o * (1 - damp) + c.s * damp; c.b[c.i] = inp + c.s * room; c.i = (c.i + 1) % c.b.length; acc += o;
      }
      for (const a of ab) { const bo = a.b[a.i]; const o = -acc + bo; a.b[a.i] = acc + bo * 0.5; a.i = (a.i + 1) % a.b.length; acc = o; }
      y[i] = acc * wet;
    }
  }
  return out;
}

// ------------------------------------------------------------------- bus ---
// Stereo bus on a beat grid. place(sig, beat, {gain, pan, at:'start'|seconds-lead})
export class Bus {
  constructor(duration, { bpm, offset = 0 } = {}) {
    this.n = sec(duration + 3); this.L = new Float32Array(this.n); this.R = new Float32Array(this.n);
    this.period = bpm ? 60 / bpm : 0.5; this.offset = offset;
  }
  t(beat) { return this.offset + beat * this.period; }
  add(sig, tSec, { gain: g = 1, pan = 0 } = {}) {
    const at = Math.round(tSec * SR);
    if (Array.isArray(sig)) { add(this.L, sig[0], at, g); add(this.R, sig[1], at, g); return this; }
    const a = (pan + 1) * Math.PI / 4;
    add(this.L, sig, at, g * Math.cos(a) * Math.SQRT2); add(this.R, sig, at, g * Math.sin(a) * Math.SQRT2);
    return this;
  }
  beat(sig, beat, opts) { return this.add(sig, this.t(beat), opts); }
  mixInto(dst, g = 1) { add(dst.L, this.L, 0, g); add(dst.R, this.R, 0, g); return dst; }
  reverb(send = 0.25, opts) { const m = new Float32Array(this.n); for (let i = 0; i < this.n; i++) m[i] = (this.L[i] + this.R[i]) * 0.5; const [l, r] = freeverb(m, opts); add(this.L, l, 0, send); add(this.R, r, 0, send); return this; }
  // Sidechain-style duck triggered at times (s).
  duck(times, depth = 0.6, release = 0.18) {
    const env = new Float32Array(this.n).fill(1);
    for (const t of times) { const s = Math.round(t * SR); for (let i = 0; i < sec(release * 3); i++) { const j = s + i; if (j >= 0 && j < this.n) env[j] = Math.min(env[j], 1 - depth * Math.exp(-i / SR / release) * Math.min(1, i / sec(0.004))); } }
    mul(this.L, env); mul(this.R, env); return this;
  }
  trim(duration) { const n = sec(duration); this.L = this.L.slice(0, n); this.R = this.R.slice(0, n); this.n = n; return this; }
}

// -------------------------------------------------------------- analysis ---
// In-place radix-2 FFT on re/im arrays (length power of 2).
export function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) { let b = n >> 1; for (; j & b; b >>= 1) j ^= b; j ^= b; if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; } }
  for (let len = 2; len <= n; len <<= 1) {
    const a = -TAU / len, wr = Math.cos(a), wi = Math.sin(a);
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const ur = re[i + k], ui = im[i + k], vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci, vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
        re[i + k] = ur + vr; im[i + k] = ui + vi; re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
        const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
      }
    }
  }
}
// Spectral-flux onset envelope (log-magnitude, half-wave rectified).
// Returns { env: Float32Array, hop, rate } where rate = frames per second.
export function onsetEnvelope(x, { hop = 256, size = 1024, fmax = SR / 2 } = {}) {
  const frames = Math.max(0, Math.floor((x.length - size) / hop)), env = new Float32Array(frames);
  const win = new Float32Array(size).map((_, i) => 0.5 - 0.5 * Math.cos(TAU * i / size));
  const kmax = Math.min(size / 2, Math.round(fmax / SR * size));
  let prev = new Float32Array(kmax);
  const re = new Float64Array(size), im = new Float64Array(size);
  for (let f = 0; f < frames; f++) {
    for (let i = 0; i < size; i++) { re[i] = x[f * hop + i] * win[i]; im[i] = 0; }
    fft(re, im);
    const cur = new Float32Array(kmax); let s = 0;
    for (let k = 1; k < kmax; k++) { cur[k] = Math.log1p(100 * Math.hypot(re[k], im[k])); const d = cur[k] - prev[k]; if (d > 0) s += d; }
    env[f] = s; prev = cur;
  }
  return { env, hop, rate: SR / hop, size };
}
// Peak-pick onsets (seconds) from an envelope with adaptive threshold.
export function pickOnsets({ env, hop, size }, { delta = 0.07, wait = 0.05, pre = 0.1 } = {}) {
  const max = env.reduce((m, v) => Math.max(m, v), 1e-9), w = Math.round(pre * SR / hop), gap = Math.round(wait * SR / hop), out = [];
  let last = -1e9;
  for (let i = 1; i < env.length - 1; i++) {
    const v = env[i] / max;
    if (v < env[i - 1] / max || v < env[i + 1] / max) continue;
    let m = 0; for (let j = Math.max(0, i - w); j < i; j++) m += env[j] / max; m /= Math.max(1, Math.min(i, w));
    if (v > m + delta && i - last >= gap) { out.push((i * hop + size / 2) / SR); last = i; }
  }
  return out;
}
