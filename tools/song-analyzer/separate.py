"""Vocal / instrumental split with a pre-trained MDX-Net ONNX model (UVR's public models,
e.g. UVR-MDX-NET-Voc_FT.onnx). Only numpy + librosa + onnxruntime: no torch.

    from separate import separate_vocals
    vocals = separate_vocals(y, "UVR-MDX-NET-Voc_FT.onnx")   # y: (2, n) float32 @ 44.1 kHz

The model sees 256-frame chunks of a 7680-point STFT (hop 1024), the first 3072 bins, as
[L.re, L.im, R.re, R.im] and returns the vocal spectrum in the same layout. Chunks overlap by
n_fft/2 on each side and only their centres are kept, so there are no seams.
"""

import numpy as np
import librosa

N_FFT, HOP, DIM_F, DIM_T = 7680, 1024, 3072, 256
COMPENSATE = 1.021      # the model's published level compensation for its primary stem


def _stft(x):
    S = np.stack([librosa.stft(c, n_fft=N_FFT, hop_length=HOP, window="hann", center=True, pad_mode="reflect")
                  for c in x])                                   # (2, F, T)
    S = S[:, :DIM_F]
    return np.stack([S[0].real, S[0].imag, S[1].real, S[1].imag]).astype(np.float32)


def _istft(spec, length):
    F = N_FFT // 2 + 1
    out = []
    for c in range(2):
        z = np.zeros((F, spec.shape[-1]), np.complex64)
        z[:DIM_F] = spec[2 * c] + 1j * spec[2 * c + 1]
        out.append(librosa.istft(z, hop_length=HOP, n_fft=N_FFT, window="hann", center=True, length=length))
    return np.stack(out)


def separate_vocals(y, model_path, batch=2, denoise=True, progress=True):
    import onnxruntime as ort
    sess = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    name = sess.get_inputs()[0].name
    chunk = HOP * (DIM_T - 1)
    trim = N_FFT // 2
    gen = chunk - 2 * trim
    n = y.shape[1]
    pad = gen - (n % gen)
    mix = np.concatenate([np.zeros((2, trim), np.float32), y.astype(np.float32),
                          np.zeros((2, pad + trim), np.float32)], axis=1)
    starts = list(range(0, n + pad, gen))
    out = np.zeros((2, n + pad), np.float32)
    for b0 in range(0, len(starts), batch):
        group = starts[b0:b0 + batch]
        specs = np.stack([_stft(mix[:, s:s + chunk]) for s in group])
        pred = sess.run(None, {name: specs})[0]
        if denoise:     # the model is not sign-symmetric; averaging f(x) and -f(-x) cancels its noise floor
            pred = 0.5 * (pred - sess.run(None, {name: -specs})[0])
        for s, p in zip(group, pred):
            w = _istft(p, chunk)
            out[:, s:s + gen] = w[:, trim:trim + gen]
        if progress:
            print(f"\r  separating vocals {min(b0 + batch, len(starts))}/{len(starts)} chunks", end="", flush=True)
    if progress:
        print()
    return out[:, :n] * COMPENSATE
