#!/bin/bash
# FINAL BUILD CYCLE: checkpoint -> rootfs -> squashfs -> ISO (space-safe, atomic steps)
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
. "$BASE/tools-env.sh"

# 1) fetch checkpoint (only if no rootfs yet)
if [ ! -d "$R/usr/bin" ]; then
  TOKEN=$(cat /home/z/my-project/.gh-token)
  AID=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/repos/f1999society-cmd/bnasec-os/releases/tags/checkpoint | python3 -c "import json,sys;print(json.load(sys.stdin)['assets'][0]['id'])")
  SIGNED=$(curl -s -I -H "Authorization: token $TOKEN" -H "Accept: application/octet-stream" "https://api.github.com/repos/f1999society-cmd/bnasec-os/releases/assets/$AID" | grep -i "^location:" | cut -d' ' -f2 | tr -d '\r')
  curl -sL -C - -o "$BASE/checkpoint.squashfs" "$SIGNED"
  echo "checkpoint: $(stat -c %s $BASE/checkpoint.squashfs) bytes"
fi

# 2) extract rootfs (full, verified)
if [ ! -f "$R/usr/local/sbin/bnasec-persist-setup" ]; then
  rm -rf "$R"
  unsquashfs -q -d "$R" "$BASE/checkpoint.squashfs" > /dev/null 2>&1
  test -f "$R/usr/local/sbin/bnasec-persist-setup" || { echo "EXTRACTION INCOMPLETE"; exit 1; }
  test -f "$R/usr/local/bin/wpscan" || { echo "wpscan missing"; exit 1; }
  rm -f "$BASE/checkpoint.squashfs"
  echo "rootfs restored"
fi

# 2b) re-apply fixes the checkpoint predates
cd "$BASE"
cp "$BASE/../scripts/reference-bnasec-persist-setup" "$R/usr/local/sbin/bnasec-persist-setup"
chmod +x "$R/usr/local/sbin/bnasec-persist-setup"

mkdir -p "$R/boot" "$R/etc/initramfs-tools/hooks"
cp "$BASE/isostage/vmlinuz" "$R/boot/vmlinuz-6.12.107+deb13-amd64"
cp "$BASE/assets/hook-bnasec-udev-libs" "$R/etc/initramfs-tools/hooks/bnasec-udev-libs"
chmod +x "$R/etc/initramfs-tools/hooks/bnasec-udev-libs" "$R/usr/local/sbin/bnasec-persist-setup"
cd /home/z/my-project && . scripts/bnasec-chroot-env.sh
bnasec_run "mkinitramfs -o /boot/initrd.img-6.12.107+deb13-amd64 6.12.107+deb13-amd64" 2>&1 | tail -1
test -f "$R/boot/initrd.img-6.12.107+deb13-amd64" || { echo "initramfs failed"; exit 1; }
cd "$BASE"
rm -f "$BASE/live/filesystem.squashfs"
# 3) squashfs (rootfs still present)
if [ ! -f "$BASE/live/filesystem.squashfs" ]; then
  mkdir -p "$BASE/live"
  mksquashfs "$R" "$BASE/live/filesystem.squashfs" \
    -comp zstd -Xcompression-level 6 -b 1M -all-root -noappend \
    -e boot -wildcards -e 'var/cache/apt/*' 'var/lib/apt/lists/*' 2>&1 | tail -1
fi

# 4) stage isodir (hardlinks)
I="$BASE/minichroot/isodir"
rm -rf "$I"
mkdir -p "$I/live" "$I/boot/grub/themes/bnasec" "$I/boot/grub/fonts"
ln "$R/boot/vmlinuz-6.12.107+deb13-amd64" "$I/live/vmlinuz"
ln "$R/boot/initrd.img-6.12.107+deb13-amd64" "$I/live/initrd.img"
ln "$BASE/live/filesystem.squashfs" "$I/live/filesystem.squashfs"
ln "$BASE/isostage/vmlinuz" "$I/live/vmlinuz" 2>/dev/null || true
cp "$BASE/assets/grub-bg.png" "$BASE"/assets/menu_*.png "$I/boot/grub/themes/bnasec/"
cp "$BASE/tools-root/usr/share/grub/unicode.pf2" "$I/boot/grub/fonts/unicode.pf2"
cp "$BASE/assets/iso-grub.cfg" "$I/boot/grub/grub.cfg"
cp "$BASE/assets/iso-theme.txt" "$I/boot/grub/themes/bnasec/theme.txt"

# 5) free rootfs BEFORE the 1.55G iso write
rm -rf "$R"
df -h / | tail -1
echo "--- rootfs freed, isodir staged ---"
ls -la "$I/live/"
