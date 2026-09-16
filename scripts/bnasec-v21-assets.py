#!/home/z/.venv/bin/python3
"""BNAsec v2.1.0 asset generation from user images:
   1.jpg -> plymouth watermark (dragon+B+tagline) + loading-bar animation frames + spinner throbber frames + grub bg
   2.jpg -> default wallpaper    3.jpg -> optional wallpaper
"""
from PIL import Image, ImageDraw, ImageFilter
import os, math

UP = "/home/z/my-project/upload"
T = "/home/z/my-project/bnasec-build/rootfs/usr/share/plymouth/themes/bnasec"
BG = "/home/z/my-project/bnasec-build/assets"
WALL = "/home/z/my-project/bnasec-build/rootfs/usr/share/backgrounds/bnasec"
os.makedirs(T, exist_ok=True)
os.makedirs(WALL, exist_ok=True)

img1 = Image.open(f"{UP}/1.jpg").convert("RGBA")
img2 = Image.open(f"{UP}/2.jpg").convert("RGB")
img3 = Image.open(f"{UP}/3.jpg").convert("RGB")
W, H = img1.size  # 1672x941

# ---------- 1) watermark: dragon + BNAsec OS + tagline (crop from 1.jpg) ----------
# luminance-alpha extraction: glowing logo/text on black -> transparent bg, no box edges
crop = img1.crop((460, 100, 1210, 640))  # 750x540 includes full tagline
px = crop.load()
out = Image.new("RGBA", crop.size, (0, 0, 0, 0))
po = out.load()
for y in range(crop.size[1]):
    for x in range(crop.size[0]):
        r, g, b = px[x, y][:3]
        lum = max(r, g, b)
        a = min(255, int(lum * 1.9))
        if a:
            po[x, y] = (r, g, b, a)
logo = out
logo.save(f"{T}/bnasec-logo.png")
logo.save(f"{T}/watermark.png")
print("watermark:", logo.size)

# ---------- 2) loading-bar animation frames (36) — faithful to 1.jpg bar ----------
BAR_W, BAR_H = 340, 14
TRACK = (255, 255, 255, 38)      # faint track
FILL_TOP = (70, 150, 255, 255)   # blue gradient
FILL_BOT = (30, 90, 220, 255)
GLOW = (90, 170, 255, 110)
N_ANIM = 36
os.makedirs("/tmp/animwork", exist_ok=True)
for i in range(1, N_ANIM + 1):
    f = Image.new("RGBA", (BAR_W + 20, BAR_H + 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(f)
    # track (rounded)
    d.rounded_rectangle([10, 10, BAR_W + 10, BAR_H + 10], radius=BAR_H // 2, outline=TRACK, width=2, fill=(255, 255, 255, 14))
    # progress fraction: fills 0->1 over first 30 frames, holds + pulsing glow at end
    frac = min(1.0, i / 30.0)
    fill_w = int((BAR_W - 4) * frac)
    if fill_w > BAR_H:
        # glow layer
        glow = Image.new("RGBA", f.size, (0, 0, 0, 0))
        dg = ImageDraw.Draw(glow)
        dg.rounded_rectangle([12, 12, 12 + fill_w, BAR_H + 8], radius=BAR_H // 2, fill=GLOW)
        glow = glow.filter(ImageFilter.GaussianBlur(3))
        f.alpha_composite(glow)
        # solid fill with vertical gradient
        fill = Image.new("RGBA", (fill_w, BAR_H), (0, 0, 0, 0))
        df = ImageDraw.Draw(fill)
        for yy in range(BAR_H):
            t = yy / max(1, BAR_H - 1)
            c = tuple(int(FILL_TOP[k] * (1 - t) + FILL_BOT[k] * t) for k in range(3)) + (255,)
            df.line([(0, yy), (fill_w, yy)], fill=c)
        # moving highlight stripe
        hx = int((i * (fill_w + 30) / N_ANIM)) % max(1, fill_w + 30)
        x0, x1 = hx - 18, min(fill_w, hx - 6)
        if x1 >= x0 and x0 >= 0:
            stripe = Image.new("RGBA", fill.size, (0, 0, 0, 0))
            ds = ImageDraw.Draw(stripe)
            ds.rectangle([x0, 0, x1, BAR_H], fill=(255, 255, 255, 60))
            fill.alpha_composite(stripe)
        mask_f = Image.new("L", (fill_w, BAR_H), 0)
        ImageDraw.Draw(mask_f).rounded_rectangle([0, 0, fill_w, BAR_H], radius=BAR_H // 2, fill=255)
        f.paste(fill, (12, 12), mask_f)
    # leading dot
    if 0 < frac < 1:
        cx = 12 + fill_w
        d.ellipse([cx - 3, 10 + BAR_H // 2 - 3, cx + 3, 10 + BAR_H // 2 + 3], fill=(200, 230, 255, 255))
    f.save(f"{T}/animation-{i:04d}.png")
print("animation frames: 36 ->", BAR_W + 20, "x", BAR_H + 20)

# ---------- 3) spinner throbber frames (30) — rotating arc ----------
N_TH = 30
R_OUT = 20
for i in range(1, N_TH + 1):
    s = 48
    f = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(f)
    cx = cy = s // 2
    # faint full ring
    d.arc([cx - R_OUT, cy - R_OUT, cx + R_OUT, cy + R_OUT], 0, 360, fill=(255, 255, 255, 40), width=3)
    # bright arc trailing 120 deg, rotating; head brightest
    start = i * (360 / N_TH)
    for seg in range(10):
        a0 = start - seg * 9
        alpha = max(20, 255 - seg * 25)
        col = (90, 165, 255, alpha)
        d.arc([cx - R_OUT, cy - R_OUT, cx + R_OUT, cy + R_OUT], a0 - 9, a0, fill=col, width=3)
    f.save(f"{T}/throbber-{i:04d}.png")
print("throbber frames: 30 (48x48)")

# ---------- 4) GRUB background: 1024x768 black + centered logo ----------
gbg = Image.new("RGB", (1024, 768), (6, 8, 14))
lw = 460
lh = int(logo.size[1] * lw / logo.size[0])
gbg.paste(logo.resize((lw, lh), Image.LANCZOS), ((1024 - lw) // 2, 110), logo.resize((lw, lh), Image.LANCZOS))
gbg.save(f"{BG}/grub-bg.png")
print("grub-bg: 1024x768 with 1.jpg logo")

# ---------- 5) wallpapers ----------
img2.save(f"{WALL}/bnasec-wave.jpg", quality=92)
img3.save(f"{WALL}/bnasec-red-moon.jpg", quality=92)
print("wallpapers installed: bnasec-wave.jpg (default), bnasec-red-moon.jpg (optional)")
print("=== ASSETS DONE ===")
