#!/bin/bash
# BNAsec-Arch rice part 2: wallpapers, Bibata cursor, /home/bna from skel
set -e
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS

echo "=== 1) Bibata cursor theme ==="
mkdir -p $R/usr/share/icons /tmp/bibata
if [ ! -d $R/usr/share/icons/Bibata-Modern-Ice ]; then
  curl -fsSL -o /tmp/bibata/c.tar.xz "https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.6/Bibata-Modern-Ice.tar.xz" 2>/dev/null \
    || curl -fsSL -o /tmp/bibata/c.tar.xz "https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.5/Bibata-Modern-Ice.tar.xz"
  tar -xf /tmp/bibata/c.tar.xz -C /tmp/bibata/ && ls -d /tmp/bibata/Bibata* | head -2
  cp -a /tmp/bibata/Bibata-Modern-Ice $R/usr/share/icons/ && echo "  Bibata installed"
fi
ls $R/usr/share/icons/ | grep Bibata

echo "=== 2) Catppuccin Mocha wallpapers (PIL) ==="
mkdir -p $R/usr/share/backgrounds/bnasec
python3 "$AB/scripts/bnasec-arch-wallpapers.py"
ls -la $R/usr/share/backgrounds/bnasec/

echo "=== 3) /home/bna from skel ==="
mkdir -p $R/home/bna
cp -a $R/etc/skel/. $R/home/bna/
mkdir -p $R/home/bna/Pictures/Screenshots $R/home/bna/Documents $R/home/bna/Downloads $R/home/bna/.config/bnasec
ls -la $R/home/bna/ | head -10

echo "RICE PART 2 DONE"
