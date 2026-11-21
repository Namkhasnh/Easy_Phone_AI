"""Cut Khoai_trellis.png into rig layers (tail, head, ear L/R, body), defringe the pink halo.
All layers share one canvas so SwiftUI can stack them; pivots are printed in unit coordinates."""
import sys, json
import numpy as np, cv2
from PIL import Image, ImageDraw

SRC, OUT = sys.argv[1], sys.argv[2]
im = np.array(Image.open(SRC).convert("RGBA")).astype(np.float32)
H, W = im.shape[:2]

# --- 1. defringe: pinkish pixels (R high, B > G) → fur tone, keep luminance-ish
r, g, b, a = im[..., 0], im[..., 1], im[..., 2], im[..., 3]
pink = (r > 140) & (b > g + 6) & (r > b)
im[..., 1] = np.where(pink, np.maximum(g, r * 0.70), g)
im[..., 2] = np.where(pink, im[..., 1] * 0.55, b)

def poly(points, feather=0):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    m = np.array(m).astype(np.float32) / 255
    if feather:
        m = cv2.GaussianBlur(m, (0, 0), feather)
    return m

alpha = a / 255

# --- 2. masks (canvas px of the 1205x1306 source)
collar = [(0, 640), (340, 640), (380, 680), (460, 698), (560, 684), (640, 642), (700, 592), (760, 545), (W, 545)]
head_m = poly([(0, 0), (W, 0)] + collar[::-1], feather=2)
ear_l = poly([(190, 140), (250, 95), (330, 68), (420, 58), (482, 92), (470, 130), (410, 152), (370, 188), (332, 232),
              (306, 292), (292, 362), (272, 440), (240, 452), (200, 402), (184, 300), (178, 220)], feather=3)
ear_r = poly([(640, 178), (700, 172), (760, 196), (822, 258), (866, 350), (856, 452), (804, 512), (732, 522),
              (692, 472), (666, 382), (650, 282)], feather=3)
tail = poly([(896, 800), (930, 768), (980, 755), (1060, 775), (1125, 815), (1150, 900), (1145, 1000), (1105, 1085),
             (1030, 1115), (965, 1105), (940, 1055), (926, 985), (906, 905)], feather=3)
tail_pivot, head_pivot, earl_pivot, earr_pivot = (935, 1050), (520, 690), (430, 115), (680, 200)

yy, xx = np.mgrid[0:H, 0:W]
def near(p, rad):  # 1 at the pivot, fading out to 0 at rad
    d = np.hypot(xx - p[0], yy - p[1])
    return np.clip(1 - (d - rad * 0.6) / (rad * 0.4), 0, 1)

def layer(mask):
    out = im.copy()
    out[..., 3] = a * np.clip(mask, 0, 1)
    return out

def inpaint(rgba, hole):
    """Fill `hole` (bool) with fur colour from around it; returns RGB."""
    rgb = np.clip(rgba[..., :3], 0, 255).astype(np.uint8)
    return cv2.inpaint(rgb, hole.astype(np.uint8) * 255, 9, cv2.INPAINT_TELEA).astype(np.float32)

# Head base: head minus the ears, holes near the face filled with fur, plus a hidden neck under the sweater.
ears = np.maximum(ear_l, ear_r)
head_base = layer(head_m * (1 - ears))
inside = (alpha > 0.5) & (head_m > 0.5)
face = inside & (ears < 0.5)
dist = cv2.distanceTransform((~face).astype(np.uint8), cv2.DIST_L2, 5)
band = (ears > 0.2) & (dist < 60) & inside            # strip of the ear hole next to the face
neck = poly([(360, 600), (690, 590), (700, 780), (360, 780)]) > 0.5
neck &= head_m < 0.5
# Under the ears keep the real ear fur near the face (fading out), so a turning ear never shows a smudge.
filled = inpaint(im, neck)
head_base[..., :3] = np.where(neck[..., None], filled, head_base[..., :3])
fill_a = np.where(band, a * np.clip(1 - (dist - 20) / 40, 0, 1), 0)
fill_a = np.where(neck, 255, fill_a)
head_base[..., 3] = np.maximum(head_base[..., 3], fill_a)

ear_l_layer = layer(head_m * ear_l)
ear_r_layer = layer(head_m * ear_r)
body_keep = (1 - head_m) * (1 - tail * (1 - near(tail_pivot, 90)))
body = layer(body_keep)
tail_layer = layer(tail)

# --- 3. crop + scale, save
x0, y0, x1, y1 = 160, 40, 1165, 1225
scale = 0.5
size = (round((x1 - x0) * scale), round((y1 - y0) * scale))
names = {"tail": tail_layer, "head": head_base, "earL": ear_l_layer, "earR": ear_r_layer, "body": body}
for n, arr in names.items():
    arr = np.clip(arr, 0, 255).astype(np.uint8)[y0:y1, x0:x1]
    Image.fromarray(arr, "RGBA").convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA").save(f"{OUT}/{n}.png", optimize=True)
full = np.clip(im, 0, 255).astype(np.uint8)[y0:y1, x0:x1]
Image.fromarray(full, "RGBA").convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA").save(f"{OUT}/still.png", optimize=True)

unit = lambda p: (round((p[0] - x0) / (x1 - x0), 4), round((p[1] - y0) / (y1 - y0), 4))
print(json.dumps({"size": size, "tail": unit(tail_pivot), "head": unit(head_pivot),
                  "earL": unit(earl_pivot), "earR": unit(earr_pivot)}))
