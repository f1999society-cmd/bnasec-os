#!/bin/bash
# Build squashfs + hybrid BIOS+UEFI ISO via grub-mkrescue (run inside chroot:
# its compiled-in /usr/lib/grub must resolve; isodir = hardlinks, no extra space)
# usage: bash bnasec-iso.sh [squashfs|iso|all]
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
KVER=$(ls "$R/lib/modules" | head -1)
OUT_ISO="$BASE/bnasec-2.0.0-amd64.iso"

case "${1:-all}" in
squashfs|all)
  mkdir -p "$BASE/live"
  rm -f "$BASE/live/filesystem.squashfs"
  echo "--- mksquashfs (zstd, all-root) ---"
  . "$BASE/tools-env.sh"
  mksquashfs "$R" "$BASE/live/filesystem.squashfs" \
    -comp zstd -Xcompression-level 6 -b 1M -all-root -noappend \
    -e boot -wildcards -e 'var/cache/apt/*' 'var/lib/apt/lists/*' \
    2>&1 | tail -2
  ls -la "$BASE/live/"
  ;;
esac

case "${1:-all}" in
iso|all)
  I="$R/isodir"
  rm -rf "$I" "$R/bnasec-out.iso" "$OUT_ISO"
  mkdir -p "$I/live" "$I/boot/grub/themes/bnasec" "$I/boot/grub/fonts"
  ln "$R/boot/vmlinuz-$KVER" "$I/live/vmlinuz"
  ln "$R/boot/initrd.img-$KVER" "$I/live/initrd.img"
  ln "$BASE/live/filesystem.squashfs" "$I/live/filesystem.squashfs"

  cat > "$I/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=3
loadfont /boot/grub/fonts/unicode.pf2
insmod all_video
insmod gfxterm
insmod png
insmod jpeg
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
  cat > "$I/boot/grub/themes/bnasec/theme.txt" <<'EOF'
desktop-image: "bg.png"
desktop-color: "#0a0e1a"
title-color: "#eef4fc"
title-font: "Unknown Regular 22"
menu-color: "#9aa7bd"
menu-font: "Unknown Regular 16"
menu-highlight-color: "#22d3ee"
menu-border-color: "#1b2740"
EOF
  cp "$BASE/assets/grub-bg.png" "$I/boot/grub/themes/bnasec/bg.png"
  cp "$BASE/tools-root/usr/share/grub/unicode.pf2" "$I/boot/grub/fonts/unicode.pf2"

  echo "--- grub-mkrescue inside chroot ---"
  . /home/z/my-project/scripts/bnasec-chroot-env.sh
  bnasec_run "grub-mkrescue -o /bnasec-out.iso /isodir -- -volid BNASEC" 2>&1 | tail -3
  mv "$R/bnasec-out.iso" "$OUT_ISO"
  rm -rf "$I"
  ls -la "$OUT_ISO"
  echo "--- eltorito/MBR check ---"
  "$BASE/tools-root/usr/bin/xorriso" -indev "$OUT_ISO" -report_el_torito as_mkisofs 2>/dev/null | grep -vE "NOTE|UPDATE|xorriso|Media|Drive" | head -12
  ;;
esac
