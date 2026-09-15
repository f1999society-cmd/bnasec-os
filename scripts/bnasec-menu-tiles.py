#!/usr/bin/env python3
"""GRUB menu tile PNGs for the bnasec theme (9-slice: b=center, c=selected)."""
from PIL import Image

OUT = "/home/z/my-project/bnasec-build/assets"
NAVY = (13, 20, 38, 200)
CYAN = (34, 211, 238, 230)
INK = (8, 12, 24, 170)

# menu_b.png — normal item box (translucent dark)
Image.new("RGBA", (32, 32), INK).save(f"{OUT}/menu_b.png")
# menu_c.png — selected item box (dark + cyan tint)
Image.new("RGBA", (32, 32), (20, 40, 58, 215)).save(f"{OUT}/menu_c.png")
print("menu tiles written")
