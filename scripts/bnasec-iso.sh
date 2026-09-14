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
  rm -f "$BASE/minichroot/bnasec-out.iso"
  if [ -f "$I/live/filesystem.squashfs" ] && [ -f "$I/boot/grub/grub.cfg" ]; then
    echo "--- isodir already staged, reusing ---"
  else
    rm -rf "$I"

  # stage live files: prefer rootfs+live (hardlinks, no cost), else isostage, else ISO extract
  mkdir -p "$STAGE" "$I/live" "$I/boot/grub/themes/bnasec" "$I/boot/grub/fonts"
  if [ -n "$KVER" ] && [ -f "$R/boot/vmlinuz-$KVER" ] && [ -f "$BASE/live/filesystem.squashfs" ]; then
    ln "$R/boot/vmlinuz-$KVER" "$I/live/vmlinuz"
    ln "$R/boot/initrd.img-$KVER" "$I/live/initrd.img"
    ln "$BASE/live/filesystem.squashfs" "$I/live/filesystem.squashfs"
    cp "$R/boot/vmlinuz-$KVER" "$STAGE/vmlinuz"
    cp "$R/boot/initrd.img-$KVER" "$STAGE/initrd.img"
    # squashfs data lives on via the isodir hardlink; free the live copy
    [ "${KEEP_SQUASHFS:-0}" = "1" ] || rm -f "$BASE/live/filesystem.squashfs"
  elif [ -d "$R/usr/bin" ] && [ ! -f "$STAGE/filesystem.squashfs" ]; then
    echo "--- rootfs present but squashfs missing: rebuilding ---"
    . "$BASE/tools-env.sh"
    mkdir -p "$BASE/live"
    mksquashfs "$R" "$BASE/live/filesystem.squashfs" \
      -comp zstd -Xcompression-level 6 -b 1M -all-root -noappend \
      -e boot -wildcards -e 'var/cache/apt/*' 'var/lib/apt/lists/*' 2>&1 | tail -1
    ln "$R/boot/vmlinuz-$KVER" "$I/live/vmlinuz"
    ln "$R/boot/initrd.img-$KVER" "$I/live/initrd.img"
    ln "$BASE/live/filesystem.squashfs" "$I/live/filesystem.squashfs"
    cp "$R/boot/vmlinuz-$KVER" "$STAGE/vmlinuz"; cp "$R/boot/initrd.img-$KVER" "$STAGE/initrd.img"
    [ "${KEEP_SQUASHFS:-0}" = "1" ] || rm -f "$BASE/live/filesystem.squashfs"
  elif [ -f "$STAGE/vmlinuz" ] && [ -f "$STAGE/initrd.img" ]; then
    if [ -f "$BASE/live/filesystem.squashfs" ]; then
      ln "$BASE/live/filesystem.squashfs" "$STAGE/filesystem.squashfs" 2>/dev/null || cp "$BASE/live/filesystem.squashfs" "$STAGE/"
    elif [ ! -f "$STAGE/filesystem.squashfs" ]; then
      echo "--- extracting squashfs from existing ISO ---"
      . "$BASE/tools-env.sh"
      xorriso -osirrox on -indev "$OUT_ISO" -extract /live/filesystem.squashfs "$STAGE/filesystem.squashfs" 2>&1 | tail -1
    fi
    ln "$STAGE/vmlinuz" "$I/live/vmlinuz"
    ln "$STAGE/initrd.img" "$I/live/initrd.img"
    ln "$STAGE/filesystem.squashfs" "$I/live/filesystem.squashfs"
  else
    echo "ERROR: no staging source (need rootfs+live or isostage or ISO)" >&2
    exit 1
  fi


  fi
  # space guard: rootfs data is staged (squashfs + isostage kernel/initrd)
  AVAIL=$(df -k / | awk 'NR==2{print $4}')
  if [ "$AVAIL" -lt 1800000 ] && [ -d "$R/usr/bin" ]; then
    echo "--- freeing rootfs (already staged) ---"; rm -rf "$R"
  fi

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
    grub-mkrescue -o /bnasec-out.iso /isodir -- -volid BNASEC 2>&1 | tail -2
  mv "$BASE/minichroot/bnasec-out.iso" "$OUT_ISO"
  rm -rf "$I"
  ls -la "$OUT_ISO"
  echo "--- eltorito/MBR check ---"
  xorriso -indev "$OUT_ISO" -report_el_torito as_mkisofs 2>/dev/null | grep -E "^-b|^-e|--grub2-mbr|--efi-boot|protective" | head -8
  ;;
esac
