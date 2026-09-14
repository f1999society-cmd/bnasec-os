#!/bin/bash
# Build squashfs + hybrid BIOS+UEFI ISO via grub-mkrescue (run inside chroot:
# its compiled-in /usr/lib/grub must resolve; isodir = hardlinks, no extra space)
# usage: bash bnasec-iso.sh [squashfs|iso|all]
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
KVER=$(ls "$R/lib/modules" 2>/dev/null | head -1 || true)
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
  I="$BASE/minichroot/isodir"
  STAGE="$BASE/isostage"
  rm -rf "$I" "$BASE/minichroot/bnasec-out.iso"

  # stage live files: reuse isostage, else rootfs, else extract from existing ISO
  mkdir -p "$STAGE"
  if [ ! -f "$STAGE/filesystem.squashfs" ]; then
    if [ -f "$BASE/live/filesystem.squashfs" ] && [ -f "$R/boot/vmlinuz-$KVER" ]; then
      cp "$BASE/live/filesystem.squashfs" "$STAGE/"
      cp "$R/boot/vmlinuz-$KVER" "$STAGE/vmlinuz"
      cp "$R/boot/initrd.img-$KVER" "$STAGE/initrd.img"
    else
      echo "--- staging live files from existing ISO ---"
      . "$BASE/tools-env.sh"
      for pair in "vmlinuz:vmlinuz" "initrd.img:initrd.img" "filesystem.squashfs:filesystem.squashfs"; do
        src="${pair%%:*}"; dst="${pair##*:}"
        xorriso -osirrox on -indev "$OUT_ISO" -extract "/live/$src" "$STAGE/$dst" 2>&1 | tail -1
      done
    fi
  fi

  mkdir -p "$I/live" "$I/boot/grub/themes/bnasec" "$I/boot/grub/fonts"
  ln "$STAGE/vmlinuz" "$I/live/vmlinuz"
  ln "$STAGE/initrd.img" "$I/live/initrd.img"
  ln "$STAGE/filesystem.squashfs" "$I/live/filesystem.squashfs"

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
title-text: ""
title-color: "#eef4fc"
title-font: "Unknown Regular 20"

+ boot_menu {
  left = 12%
  top = 30%
  width = 76%
  height = 50%
  item_font = "Unknown Regular 16"
  item_color = "#9aa7bd"
  selected_item_color = "#22d3ee"
  item_height = 34
  item_padding = 6
  item_spacing = 6
}
EOF
  cp "$BASE/assets/grub-bg.png" "$I/boot/grub/themes/bnasec/bg.png"
  cp "$BASE/tools-root/usr/share/grub/unicode.pf2" "$I/boot/grub/fonts/unicode.pf2"

  echo "--- grub-mkrescue inside minichroot ---"
  . "$BASE/tools-env.sh"
  export FAKECHROOT_CMD_SUBST="/usr/sbin/ldconfig=$BASE/tools-root/usr/libexec/mmdebstrap/ldconfig.fakechroot:/sbin/ldconfig=$BASE/tools-root/usr/libexec/mmdebstrap/ldconfig.fakechroot:/usr/sbin/chroot=$BASE/tools-root/usr/sbin/chroot.fakechroot:/sbin/chroot=$BASE/tools-root/usr/sbin/chroot.fakechroot:/usr/bin/ldd=$BASE/tools-root/usr/bin/ldd.fakechroot:/bin/ldd=$BASE/tools-root/usr/bin/ldd.fakechroot:/bin/ischroot=/bin/true:/usr/bin/ischroot=/bin/true"
  export FAKECHROOT_EXCLUDE_PATH="/dev:/proc:/sys"
  rm -f "$OUT_ISO"
  fakechroot fakeroot chroot "$BASE/minichroot" /usr/bin/env LC_ALL=C HOME=/root \
    grub-mkrescue -o /bnasec-out.iso /isodir -- -volid BNASEC 2>&1 | tail -2
  mv "$BASE/minichroot/bnasec-out.iso" "$OUT_ISO"
  rm -rf "$I"
  ls -la "$OUT_ISO"
  echo "--- eltorito/MBR check ---"
  xorriso -indev "$OUT_ISO" -report_el_torito as_mkisofs 2>/dev/null | grep -E "^-b|^-e|--grub2-mbr|--efi-boot|protective" | head -8
  ;;
esac
