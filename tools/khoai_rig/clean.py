"""Matted video frames → clean, cropped RGBA frames: remove the grey background left in soft fur edges
(un-mix bg colour), drop the pink halo, crop to one shared box (all clips), scale to the app height."""
import sys, glob, os
import numpy as np
from PIL import Image
src, dst, H_OUT = sys.argv[1], sys.argv[2], int(sys.argv[3])
BOX = (0, 300, 720, 1200)              # shared crop for every clip (720x1280 source, Khoai sits in the lower part)
BG = np.array([236, 236, 236], np.float32)
os.makedirs(dst, exist_ok=True)
for i, f in enumerate(sorted(glob.glob(f"{src}/*.png"))):
    a = np.array(Image.open(f).convert("RGBA")).astype(np.float32)
    al = a[..., 3:4] / 255
    rgb = np.where(al > 0.02, (a[..., :3] - (1 - al) * BG) / np.maximum(al, 0.02), 0)
    rgb = np.clip(rgb, 0, 255)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    pink = (r > 140) & (b > g + 6) & (r > b)
    g2 = np.where(pink, np.maximum(g, r * 0.70), g)
    rgb[..., 2] = np.where(pink, g2 * 0.55, b); rgb[..., 1] = g2
    out = np.concatenate([rgb, al * 255], axis=2).astype(np.uint8)
    im = Image.fromarray(out, "RGBA").crop(BOX)
    w = round(im.width * H_OUT / im.height)
    im.convert("RGBa").resize((w, H_OUT), Image.LANCZOS).convert("RGBA").save(f"{dst}/p{i:03d}.png")
print("ok", i + 1, w, H_OUT)
