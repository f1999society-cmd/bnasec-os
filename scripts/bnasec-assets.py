#!/usr/bin/env python3
"""Generate BNAsec brand assets: plymouth logo, GNOME wallpaper, GRUB background."""
import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = "/home/z/my-project/bnasec-build/assets"
os.makedirs(OUT, exist_ok=True)

CYAN = (34, 211, 238)
NAVY = (13, 20, 38)
INK = (8, 12, 24)
WHITE = (238, 244, 252)
GRAY = (120, 136, 160)
DEJAVU_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
DEJAVU = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def shield_pts(cx, cy, w, h):
    """Classic shield outline points around center."""
    hw, hh = w / 2, h / 2
    return [
        (cx - hw, cy - hh + 6),
        (cx, cy - hh - 6),
        (cx + hw, cy - hh + 6),
        (cx + hw, cy + hh * 0.18),
        (cx + hw * 0.62, cy + hh * 0.62),
        (cx, cy + hh + 8),
        (cx - hw * 0.62, cy + hh * 0.62),
        (cx - hw, cy + hh * 0.18),
    ]


def draw_logo(size=512, ss=4):
    """Supersampled shield + B mark, transparent background."""
    S = size * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = S / 2, S * 0.47
    sw, sh = S * 0.62, S * 0.72

    # soft outer glow
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.polygon(shield_pts(cx, cy, sw * 1.06, sh * 1.06), fill=(34, 211, 238, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.05))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)

    # shield fill + gradient-ish overlay
    d.polygon(shield_pts(cx, cy, sw, sh), fill=NAVY + (255,))
    for i in range(int(sh)):
        y = cy - sh / 2 + i
        a = int(70 * (1 - i / sh))
        d.line([(cx - sw / 2, y), (cx + sw / 2, y)], fill=(20, 32, 60, a))
    d.polygon(shield_pts(cx, cy, sw, sh), outline=CYAN + (255,), width=ss * 7)

    # inner shield accent
    d.polygon(shield_pts(cx, cy, sw * 0.84, sh * 0.85), outline=(34, 211, 238, 90), width=ss * 2)

    # the B (custom-built from bars + bowls so it reads at 48px)
    bw, bh = sw * 0.36, sh * 0.46
    bx, by = cx - bw / 2 + sw * 0.02, cy - bh / 2
    bar_w = bh * 0.16
    d.rounded_rectangle([bx, by, bx + bar_w, by + bh], radius=bar_w * 0.3, fill=WHITE)
    bowl = bh * 0.42
    for oy in (by, by + bh - bowl * 1.02):
        d.rounded_rectangle(
            [bx + bar_w * 0.35, oy, bx + bw + sw * 0.05, oy + bowl],
            radius=bowl / 2, outline=WHITE, width=ss * 6,
        )
    return img.resize((size, size), Image.LANCZOS)


def hexgrid(size, spacing, color, width=1, alpha=(0, 0)):
    """Faint hexagonal grid layer."""
    w, h = size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = spacing / 2
    dx = r * math.sqrt(3)
    row = 0
    y = -r
    while y < h + r:
        x = -r * 1.5 if row % 2 else -r * 0.75
        while x < w + r * 2:
            pts = [
                (x + r * math.cos(math.radians(a)), y + r * math.sin(math.radians(a)))
                for a in range(30, 391, 60)
            ]
            d.polygon(pts, outline=color + (18,), width=width)
            x += dx
        y += r * 1.5
        row += 1
    return layer


def gradient_bg(w, h):
    img = Image.new("RGB", (w, h), INK)
    d = ImageDraw.Draw(img)
    top, bot = (10, 14, 26), (16, 24, 44)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bot)))
    return img.convert("RGBA")


def watermark(img, logo, box, opacity=255):
    lw, lh = box
    lg = logo.resize((lw, lh), Image.LANCZOS)
    if opacity < 255:
        a = lg.split()[3].point(lambda p: p * opacity // 255)
        lg.putalpha(a)
    return lg


logo = draw_logo(512)
logo.save(f"{OUT}/bnasec-logo.png")

# ---- wallpaper 1920x1080 ----
W, H = 1920, 1080
wp = gradient_bg(W, H)
wp = Image.alpha_composite(wp, hexgrid((W, H), 120, CYAN))
lg = watermark(wp, logo, (300, 300), 255)
wp.alpha_composite(lg, (W // 2 - 150, int(H * 0.16)))
d = ImageDraw.Draw(wp)
f1 = ImageFont.truetype(DEJAVU_B, 148)
f2 = ImageFont.truetype(DEJAVU, 40)
t = "BNAsec"
tw = d.textlength(t, font=f1)
d.text((W / 2 - tw / 2, H * 0.52), t, font=f1, fill=WHITE)
d.rounded_rectangle(
    [W / 2 - tw / 2 + 6, H * 0.52 + 168, W / 2 - tw / 2 + 26, H * 0.52 + 188],
    radius=10, fill=CYAN,
)
s = "security testing platform"
sw_ = d.textlength(s, font=f2)
d.text((W / 2 - sw_ / 2, H * 0.52 + 200), s, font=f2, fill=GRAY)
wp.convert("RGB").save(f"{OUT}/bnasec-wallpaper.png")

# ---- grub background 1024x768 ----
W2, H2 = 1024, 768
gb = gradient_bg(W2, H2)
gb = Image.alpha_composite(gb, hexgrid((W2, H2), 80, CYAN))
lg = watermark(gb, logo, (190, 190))
gb.alpha_composite(lg, (W2 // 2 - 95, int(H2 * 0.10)))
d = ImageDraw.Draw(gb)
f3 = ImageFont.truetype(DEJAVU_B, 86)
t = "BNAsec 2.0"
tw = d.textlength(t, font=f3)
d.text((W2 / 2 - tw / 2, H2 * 0.78), t, font=f3, fill=WHITE)
gb.convert("RGB").save(f"{OUT}/grub-bg.png")

for f in ("bnasec-logo.png", "bnasec-wallpaper.png", "grub-bg.png"):
    p = f"{OUT}/{f}"
    im = Image.open(p)
    print(f, im.size, os.path.getsize(p) // 1024, "KB")
