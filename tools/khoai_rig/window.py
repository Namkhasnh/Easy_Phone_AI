"""Listening clip "Khoai in a round window" → square opaque frames of the window only (D-327, owner 2026-11-22).
v2 (owner: "nham nhở", tail sticks out of the ring): no cut-out any more. Fit the clip's gold ring (an ellipse),
keep only the inside of the window, stretched to a circle (~3 %) (the app clips it to a circle and draws a clean honey ring on top), fill the parts the AI clip
cut off at the sides with the window colour (feathered), close the loop.
Usage: window.py <frames_dir 720x1280 or 1080x1920> <out_dir> <size>"""
import sys, glob, os
import numpy as np
from PIL import Image

fdir, out, SIZE = sys.argv[1], sys.argv[2], int(sys.argv[3])
os.makedirs(out, exist_ok=True)
fs = sorted(glob.glob(f"{fdir}/*.png"))

def fit_ring(i):
    """The ring is a slight ellipse (camera a bit above). Fit x²/ax² + y²/ay² near a first guess, using the arc
    away from Khoai (upper half + the far left / right), so golden fur never counts as ring."""
    a = np.array(Image.open(fs[i]).convert("RGB")).astype(float)
    h, w = a.shape[:2]
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    ys, xs = np.nonzero((r > 120) & (r - b > 60) & (g < r))
    xs, ys = xs.astype(float), ys.astype(float)
    x0, y0, ax, ay = w * 0.5076, h * 0.4664, w * 0.571, h * 0.331      # 720x1280 fit: 365.5, 597, 411, 423.5
    near = np.abs(np.hypot((xs - x0) / ax, (ys - y0) / ay) - 1) < 0.05
    away = (ys < y0) | (np.abs(xs - x0) > 0.6 * ax)
    X, Y = xs[near & away], ys[near & away]
    for _ in range(3):
        p = np.linalg.lstsq(np.c_[X * X, Y * Y, X, Y], np.ones(len(X)), rcond=None)[0]
        A, C, D, E = p
        x0, y0 = -D / (2 * A), -E / (2 * C)
        k = 1 + A * x0 * x0 + C * y0 * y0
        ax, ay = np.sqrt(k / A), np.sqrt(k / C)
        keep = np.abs(np.hypot((X - x0) / ax, (Y - y0) / ay) - 1) < 0.02
        X, Y = X[keep], Y[keep]
    return x0, y0, ax, ay

fits = [fit_ring(i) for i in range(0, len(fs), 10)]
cx, cy, ax, ay = (np.median([f[k] for f in fits]) for k in range(4))
inset = 0.04 * ax                                      # half the ring + a little: stay inside the gold
rx, ry = ax - inset, ay - inset
x0, y0 = int(round(cx - rx)), int(round(cy - ry))
sw, sh = int(round(2 * rx)), int(round(2 * ry))
first = np.array(Image.open(fs[0]).convert("RGB")).astype(np.float32)
H, W = first.shape[:2]
win = np.median(first[int(cy) - 30:int(cy) + 30, 8:28].reshape(-1, 3), axis=0)
yy, xx = np.mgrid[0:sh, 0:sw]
fx = np.clip(np.minimum(xx + x0, W - 1 - (xx + x0)) / 24, 0, 1)
fy = np.clip(np.minimum(yy + y0, H - 1 - (yy + y0)) / 24, 0, 1)
wgt = (fx * fy)[..., None]

def window(path):
    a = np.array(Image.open(path).convert("RGB")).astype(np.float32)
    can = np.tile(win, (sh, sw, 1)).astype(np.float32)
    sx0, sy0, sx1, sy1 = max(x0, 0), max(y0, 0), min(x0 + sw, W), min(y0 + sh, H)
    can[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = a[sy0:sy1, sx0:sx1]
    return can * wgt + win * (1 - wgt)

frames = [window(f) for f in fs]
FADE = 6
for i in range(FADE):
    t = (i + 1) / (FADE + 1); j = len(frames) - FADE + i
    frames[j] = frames[j] * (1 - t) + frames[0] * t
frames = frames[:-1]
for i, fr in enumerate(frames):
    Image.fromarray(np.clip(fr, 0, 255).astype(np.uint8), "RGB").resize((SIZE, SIZE), Image.LANCZOS).save(f"{out}/p{i:03d}.png")
print("ring", round(cx, 1), round(cy, 1), round(ax, 1), round(ay, 1), "window", win.round(), "frames", len(frames), "box", sw, sh)
