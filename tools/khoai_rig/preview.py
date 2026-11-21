"""Compose the rig layers with given angles to check seams. Usage: preview.py dir pivots.json out.png [bg]"""
import sys, json
from PIL import Image

d, piv, out = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3]
bg = sys.argv[4] if len(sys.argv) > 4 else "white"
L = {n: Image.open(f"{d}/{n}.png") for n in ["tail", "head", "earL", "earR", "body", "still"]}
W, H = L["body"].size

def rot(img, deg, p):
    c = (p[0] * W, p[1] * H)
    return img.convert("RGBa").rotate(deg, resample=Image.BICUBIC, center=c).convert("RGBA")

poses = [("rest", 0, 0, 0, 0), ("tilt L", 6, -5, 5, 12), ("tilt R", -6, 5, -5, -12), ("ears", 0, 8, -8, 0)]
sheet = Image.new("RGBA", (W * (len(poses) + 1), H), bg)
sheet.alpha_composite(L["still"], (0, 0))
for i, (_, head, el, er, tail) in enumerate(poses, start=1):
    c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    c.alpha_composite(rot(L["tail"], tail, piv["tail"]))
    hg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hg.alpha_composite(L["head"])
    hg.alpha_composite(rot(L["earL"], el, piv["earL"]))
    hg.alpha_composite(rot(L["earR"], er, piv["earR"]))
    c.alpha_composite(rot(hg, head, piv["head"]))
    c.alpha_composite(L["body"])
    sheet.alpha_composite(c, (W * i, 0))
sheet.convert("RGB").save(out)
