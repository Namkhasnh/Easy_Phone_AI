"""Listening clip "Khoai clinging to a round window" → square transparent frames (D-327, owner 2026-11-22).
The AI clip's gold ring is cut off at the frame sides, so: fit the ring, redraw a complete ring + white window,
put the video inside the window and Khoai (Apple Vision matte) on top everywhere, so paws can reach over the ring.
Usage: window.py <frames_dir 720x1280> <matte_dir> <out_dir> <size>"""
import sys, glob, os
import numpy as np
from PIL import Image

fdir, mdir, out, SIZE = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
os.makedirs(out, exist_ok=True)
fs, ms = sorted(glob.glob(f"{fdir}/*.png")), sorted(glob.glob(f"{mdir}/*.png"))

def fit_ring(i):
    a = np.array(Image.open(fs[i]).convert("RGB")).astype(float)
    al = np.array(Image.open(ms[i]))[..., 3]
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    ys, xs = np.nonzero((r > 120) & (r - b > 60) & (g < r) & (al < 10))
    A, bb = np.c_[2 * xs, 2 * ys, np.ones(len(xs))], xs ** 2 + ys ** 2
    for _ in range(3):
        c = np.linalg.lstsq(A, bb, rcond=None)[0]
        cx, cy = c[0], c[1]; R = np.sqrt(c[2] + cx * cx + cy * cy)
        keep = np.abs(np.hypot(xs - cx, ys - cy) - R) < 8
        A, bb, xs, ys = A[keep], bb[keep], xs[keep], ys[keep]
    d = np.hypot(xs - cx, ys - cy)
    return cx, cy, np.percentile(d, 5), np.percentile(d, 95), np.median(a[ys, xs], axis=0)

fits = [fit_ring(i) for i in range(0, len(fs), 10)]
cx, cy = np.median([f[0] for f in fits]), np.median([f[1] for f in fits])
r_in, r_out = np.median([f[2] for f in fits]), np.median([f[3] for f in fits])
gold = np.median([f[4] for f in fits], axis=0)
half = r_out + 50                                   # room for paws over the ring
x0, y0 = int(round(cx - half)), int(round(cy - half)); side = int(round(2 * half))
yy, xx = np.mgrid[0:side, 0:side]
d = np.hypot(xx + x0 - cx, yy + y0 - cy)
aa = lambda e: np.clip(e + 0.5, 0, 1)               # 1 px anti-aliasing
disk = aa(r_in + 1 - d)                             # window (slightly under the ring)
ring = aa(d - r_in) * aa(r_out - d)

def place(arr):                                     # put a frame-sized array into the square canvas
    can = np.zeros((side, side) + arr.shape[2:], np.float32)
    sx0, sy0 = max(x0, 0), max(y0, 0)
    sx1, sy1 = min(x0 + side, arr.shape[1]), min(y0 + side, arr.shape[0])
    can[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = arr[sy0:sy1, sx0:sx1]
    # soft "inside the video" weight: fades to 0 over the last 16 px of the frame (hides the cut edge)
    fx = np.clip(np.minimum(xx + x0, arr.shape[1] - 1 - (xx + x0)) / 16, 0, 1)
    fy = np.clip(np.minimum(yy + y0, arr.shape[0] - 1 - (yy + y0)) / 16, 0, 1)
    return can, (fx * fy).astype(np.float32)

first = np.array(Image.open(fs[0]).convert("RGB")).astype(np.float32)
win = np.median(first[int(cy) - 20:int(cy) + 20, int(cx - r_in + 15):int(cx - r_in + 35)].reshape(-1, 3), axis=0)
frames = []
for f, m in zip(fs, ms):
    rgb, inside = place(np.array(Image.open(f).convert("RGB")).astype(np.float32))
    mat, _ = place(np.array(Image.open(m).convert("RGBA")).astype(np.float32))
    k = mat[..., 3] / 255
    # layer 1: white window (video where the frame has pixels, window colour in the cut-off sides) + gold ring
    base = rgb * inside[..., None] + win * (1 - inside[..., None])
    col = base * disk[..., None] + gold * ring[..., None]
    a1 = np.maximum(disk, ring)
    col = np.where(a1[..., None] > 0, col / np.maximum(a1, 1e-6)[..., None], 0)
    # layer 2: Khoai over everything (video colour, matte alpha), only where the frame exists
    k = k * inside
    out_a = k + a1 * (1 - k)
    out_c = (rgb * k[..., None] + col * a1[..., None] * (1 - k[..., None])) / np.maximum(out_a, 1e-6)[..., None]
    frames.append(np.concatenate([out_c * out_a[..., None], out_a[..., None] * 255], axis=2))   # premultiplied
# close the loop like clean.py: fade the last frames into the first
FADE = 6
for i in range(FADE):
    t = (i + 1) / (FADE + 1); j = len(frames) - FADE + i
    frames[j] = frames[j] * (1 - t) + frames[0] * t
frames = frames[:-1]
for i, fr in enumerate(frames):
    im = Image.fromarray(np.clip(fr, 0, 255).astype(np.uint8), "RGBa").resize((SIZE, SIZE), Image.LANCZOS)
    im.convert("RGBA").save(f"{out}/p{i:03d}.png")
print("ring", round(cx, 1), round(cy, 1), round(r_in, 1), round(r_out, 1), "gold", gold.round(), "window", win.round(), "frames", len(frames))
