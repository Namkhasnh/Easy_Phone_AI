"""Matted video frames → clean, cropped RGBA frames for the app (D-327).
Usage: clean.py <matte_dir> <original_frames_dir> <out_dir> <height>
- un-mixes the grey studio background from soft fur edges (bg colour read from the original frame's corners),
- drops the pink halo, crops to one box shared by every clip (fractions of the frame), scales to <height>,
- closes the loop: ends the clip at the frame closest to the first one, then cross-fades the last frames into it."""
import sys, glob, os
import numpy as np
from PIL import Image

matte_dir, orig_dir, dst, H_OUT = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
BOX = (0.0, 300 / 1280, 1.0, 1200 / 1280)     # same framing for every clip (Khoai sits in the lower part)
FADE = 6
os.makedirs(dst, exist_ok=True)

orig0 = np.array(Image.open(sorted(glob.glob(f"{orig_dir}/*.png"))[0]).convert("RGB")).astype(np.float32)
c = 20
corners = np.concatenate([orig0[:c, :c], orig0[:c, -c:], orig0[c * 3:c * 4, :c], orig0[c * 3:c * 4, -c:]]).reshape(-1, 3)
BG = np.median(corners, axis=0)

def clean(path):
    a = np.array(Image.open(path).convert("RGBA")).astype(np.float32)
    al = a[..., 3:4] / 255
    rgb = np.clip(np.where(al > 0.02, (a[..., :3] - (1 - al) * BG) / np.maximum(al, 0.02), 0), 0, 255)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    pink = (r > 140) & (b > g + 6) & (r > b)
    g2 = np.where(pink, np.maximum(g, r * 0.70), g)
    rgb[..., 2] = np.where(pink, g2 * 0.55, b)
    rgb[..., 1] = g2
    im = Image.fromarray(np.concatenate([rgb, al * 255], axis=2).astype(np.uint8), "RGBA")
    w, h = im.size
    im = im.crop((round(BOX[0] * w), round(BOX[1] * h), round(BOX[2] * w), round(BOX[3] * h)))
    ow = round(im.width * H_OUT / im.height)
    im = im.convert("RGBa").resize((ow, H_OUT), Image.LANCZOS)          # premultiplied while scaling
    return np.array(im).astype(np.float32)                              # premultiplied RGBa

frames = [clean(f) for f in sorted(glob.glob(f"{matte_dir}/*.png"))]
first = frames[0]
# Best loop end: the frame (in the last quarter) that looks most like the first one.
tail = range(int(len(frames) * 0.75), len(frames))
end = min(tail, key=lambda i: np.abs(frames[i] - first).mean())
frames = frames[:end + 1]
for k in range(FADE):                                                   # blend the last frames into frame 0
    t = (k + 1) / (FADE + 1)
    i = len(frames) - FADE + k
    frames[i] = frames[i] * (1 - t) + first * t
frames[-1] = first.copy()                                               # the loop restarts on an identical frame
frames = frames[:-1]
for i, f in enumerate(frames):
    Image.fromarray(np.clip(f, 0, 255).astype(np.uint8), "RGBa").convert("RGBA").save(f"{dst}/p{i:03d}.png")
print("ok frames", len(frames), "cut at", end, "bg", BG.round(1).tolist(), "size", frames[0].shape[1], H_OUT)
