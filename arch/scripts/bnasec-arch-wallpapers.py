#!/usr/bin/env python3
"""BNAsec Arch — Catppuccin Mocha wallpaper generator v2 (PIL + numpy).
Additive glow compositing on a dark base: thin bright cores + wide soft
underglow, so colors stay saturated instead of washing out to milky grey.
  bnasec-mocha-aurora.jpg  (default) — flowing aurora ribbons + stars
  bnasec-mocha-waves.jpg   — layered waves + horizon glow
  bnasec-mocha-nebula.jpg  — soft nebula + starfield
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import os

W, H = 1920, 1080
OUT = "/home/z/my-project/arch-build/airootfs/usr/share/backgrounds/bnasec"
os.makedirs(OUT, exist_ok=True)

CRUST    = (15, 15, 24)
MANTLE   = (21, 21, 33)
BASE     = (26, 26, 41)
MAUVE    = (203, 166, 247)
PINK     = (245, 194, 231)
LAVENDER = (180, 190, 254)
BLUE     = (137, 180, 250)
SAPPHIRE = (116, 199, 236)
TEAL     = (148, 226, 213)

def base_gradient():
    img = np.zeros((H, W, 3), float)
    top, mid, bot = np.array(CRUST, float), np.array(MANTLE, float), np.array(BASE, float)
    for y in range(H):
        v = y / H
        c = top + (mid - top) * (v / 0.5) if v < 0.5 else mid + (bot - mid) * ((v - 0.5) / 0.5)
        img[y, :, :] = c
    return img

def additive(img, layer_rgb, alpha):
    """img += layer * alpha (clipped)"""
    return img + layer_rgb * alpha

def ribbon_layer(color, curve, width, blur):
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.line([(int(x), int(y)) for (x, y) in curve], fill=color, width=width, joint="curve")
    return np.asarray(layer.filter(ImageFilter.GaussianBlur(blur)), float)

def add_ribbon(img, color, curve, core_w=34, core_blur=18, glow_w=120, glow_blur=110, a_core=0.85, a_glow=0.30):
    img = additive(img, ribbon_layer(color, curve, glow_w, glow_blur), a_glow)
    img = additive(img, ribbon_layer(color, curve, core_w, core_blur), a_core)
    return img

def stars(img, n=260, ymin=0, ymax=None, seed=3):
    rng = np.random.default_rng(seed)
    ymax = ymax or H
    for _ in range(n):
        sx, sy = int(rng.integers(0, W)), int(rng.integers(ymin, ymax))
        b = rng.uniform(0.15, 0.85)
        img[sy, sx] = np.minimum(255, img[sy, sx] + np.array([255, 255, 255]) * b * 0.55)
    return img

def vignette(img, strength=0.5):
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.sqrt(((xx - W/2) / (W/2)) ** 2 + ((yy - H/2) / (H/2)) ** 2) / np.sqrt(2)
    return img * (1.0 - strength * np.clip(r, 0, 1) ** 1.7)[:, :, None]

def grain(img, amount=2.0, seed=42):
    return np.clip(img + np.random.default_rng(seed).normal(0, amount, img.shape), 0, 255)

def save(img_arr, name, q=92):
    Image.fromarray(np.uint8(np.clip(img_arr, 0, 255))).save(
        os.path.join(OUT, name), "JPEG", quality=q, subsampling=1)
    print("  wrote", name)

def sine_curve(base_y, a1, a2, f1, f2, ph=0.0, drift=0.0):
    xs = np.linspace(-60, W + 60, 260)
    ys = (base_y + a1 * np.sin(f1 * xs / W * 2 * np.pi + ph)
              + a2 * np.sin(f2 * xs / W * 2 * np.pi + ph * 1.7) + drift * xs / W)
    return list(zip(xs, ys))

# ------------- 1) AURORA (default) -------------
img = base_gradient()
img = add_ribbon(img, MAUVE,    sine_curve(H*0.28, 90, 45, 1.35, 3.1, 0.0))
img = add_ribbon(img, SAPPHIRE, sine_curve(H*0.40, 110, 60, 1.05, 2.6, 1.4), a_core=0.75, a_glow=0.26)
img = add_ribbon(img, PINK,     sine_curve(H*0.52, 80, 55, 1.65, 3.6, 2.8), a_core=0.70, a_glow=0.24)
img = add_ribbon(img, TEAL,    sine_curve(H*0.20, 60, 35, 0.85, 2.2, 4.1), a_core=0.55, a_glow=0.18)
img = add_ribbon(img, LAVENDER, sine_curve(H*0.66, 100, 70, 1.15, 2.9, 5.5), a_core=0.50, a_glow=0.16)
img = stars(img, 220, 0, int(H*0.55), seed=11)
img = vignette(img, 0.52)
img = grain(img)
save(img, "bnasec-mocha-aurora.jpg")

# ------------- 2) WAVES -------------
img = base_gradient()
img = add_ribbon(img, MAUVE, [(0, H*0.30), (W*0.5, H*0.235), (W, H*0.315)], core_w=22, glow_w=90, a_core=0.6, a_glow=0.22)
xs = np.linspace(-40, W + 40, 320)
layers = [
    (H * 0.74, 34, (44, 45, 67), 0.9),
    (H * 0.84, 50, (33, 34, 52), 0.96),
    (H * 0.93, 40, (22, 22, 35), 1.0),
]
for i, (base_y, amp, col, op) in enumerate(layers):
    ys = base_y + amp * np.sin(xs / W * 2 * np.pi * 1.6 + i * 1.9) \
                + 0.45 * amp * np.sin(xs / W * 2 * np.pi * 3.4 + i)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(lay).polygon(list(zip(xs, ys)) + [(W + 50, H + 50), (-50, H + 50)],
                                fill=col + (int(255 * op),))
    la = np.asarray(lay.filter(ImageFilter.GaussianBlur(2.0)), float)
    a = la[:, :, 3:4] / 255.0
    img = img * (1 - a) + la[:, :, :3] * a
# crest highlights: thin light line along top wave edge
ys_top = H*0.74 + 34 * np.sin(xs / W * 2 * np.pi * 1.6 + 0.0) + 0.45*34*np.sin(xs / W*2*np.pi*3.4)
img = add_ribbon(img, LAVENDER, list(zip(xs, ys_top - 1)), core_w=6, core_blur=5, glow_w=40, glow_blur=45, a_core=0.5, a_glow=0.15)
img = stars(img, 150, 0, int(H*0.6), seed=21)
img = vignette(img, 0.5)
img = grain(img, seed=43)
save(img, "bnasec-mocha-waves.jpg")

# ------------- 3) NEBULA -------------
img = base_gradient()
def blob(cx, cy, radius, color, alpha):
    yy, xx = np.mgrid[0:H, 0:W]
    d2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / radius ** 2
    return (np.exp(-d2 * 2.4) * alpha)[..., None] * np.array(color, float)[None, None, :]
img += blob(W*0.32, H*0.40, 400, MAUVE,    0.32)
img += blob(W*0.60, H*0.55, 470, BLUE,     0.24)
img += blob(W*0.50, H*0.28, 320, PINK,     0.20)
img += blob(W*0.76, H*0.38, 350, SAPPHIRE, 0.18)
img += blob(W*0.20, H*0.66, 300, TEAL,     0.13)
img = stars(img, 420, seed=31)
neb_glow = Image.fromarray(np.uint8(np.clip(img, 0, 255))).filter(ImageFilter.GaussianBlur(14))
img = img * 0.72 + np.asarray(neb_glow, float) * 0.28
img = vignette(img, 0.55)
img = grain(img, 2.6, seed=44)
save(img, "bnasec-mocha-nebula.jpg")

print("wallpapers v2 done")
