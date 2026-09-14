#!/bin/bash
# Build squashfs + hybrid BIOS+UEFI ISO via grub-mkrescue
# usage: bash bnasec-iso.sh [squashfs|iso|all]
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
. "$BASE/tools-env.sh"
KVER=$(ls "$R/lib/modules" | head -1)
OUT_ISO="$BASE/bnasec-2.0.0-amd64.iso"

case "${1:-all}" in
squashfs|all)
  mkdir -p "$BASE/live"
  rm -f "$BASE/live/filesystem.squashfs"
  echo "--- mksquashfs (xz, all-root) ---"
  mksquashfs "$R" "$BASE/live/filesystem.squashfs" \
    -comp xz -b 1M -Xdict-size 100% -all-root -noappend \
    -e boot -wildcards -e 'var/cache/apt/*' 'var/lib/apt/lists/*'
  ls -la "$BASE/live/"
  ;;
esac

case "${1:-all}" in
iso|all)
  ISO="$BASE/isodir"
  rm -rf "$ISO" "$OUT_ISO"
  mkdir -p "$ISO/live" "$ISO/boot/grub/themes/bnasec" "$ISO/boot/grub/fonts"
  cp "$R/boot/vmlinuz-$KVER" "$ISO/live/vmlinuz"
  cp "$R/boot/initrd.img-$KVER" "$ISO/live/initrd.img"

  cp "$BASE/tools-root/usr/share/grub/unicode.pf2" "$ISO/boot/grub/fonts/unicode.pf2"
  cat > "$ISO/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=3
loadfont /boot/grub/fonts/unicode.pf2
insmod all_video
insmod gfxterm
set gfxmode=1024x768x32,auto
terminal_output gfxterm
search --no-floppy --set=root --file /live/vmlinuz
set theme=($root)/boot/grub/themes/bnasec/theme.txt

menuentry "BNAsec 2.0.0 — live (full persistence)" {
  linux /live/vmlinuz boot=live persistence username=bna hostname=bnasec quiet splash
  initrd /live/initrd.img
}
menuentry "BNAsec 2.0.0 — RAM-only session (no persistence)" {
  linux /live/vmlinuz boot=live toram nopersistence username=bna hostname=bnasec quiet splash
  initrd /live/initrd.img
}
menuentry "BNAsec 2.0.0 — verbose console (debug)" {
  linux /live/vmlinuz boot=live persistence username=bna hostname=bnasec console=ttyS0,115200 console=tty0
  initrd /live/initrd.img
}
EOF
  cat > "$ISO/boot/grub/themes/bnasec/theme.txt" <<'EOF'
desktop-image: "bg.png"
desktop-color: "#0a0e1a"
title-color: "#eef4fc"
title-font: "Unknown Regular 22"
menu-color: "#9aa7bd"
menu-font: "Unknown Regular 16"
menu-highlight-color: "#22d3ee"
menu-border-color: "#1b2740"
EOF
  cp "$BASE/assets/grub-bg.png" "$ISO/boot/grub/themes/bnasec/bg.png"

  echo "--- grub-mkrescue (hybrid BIOS+UEFI) ---"
  grub-mkrescue -o "$OUT_ISO" "$ISO" -- -volid BNASEC -joliet on 2>&1 | tail -4
  ls -la "$OUT_ISO"
  echo "--- eltorito/MBR check ---"
  xorriso -indev "$OUT_ISO" -report_el_torito as_mkisofs 2>/dev/null | head -8
  ;;
esac
