#!/bin/bash
# BNAsec persistence FIX + REBUILD: rootfs -> fixed initrd -> squashfs
# (ISO built separately via bnasec-iso.sh)
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
S=/home/z/my-project/scripts

echo "=== 1) free space (ISO is on GitHub Release v2.0.0, minichroot rebuildable) ==="
rm -f "$BASE/bnasec-2.0.0-amd64.iso" "$BASE/bnasec-2.0.0-amd64.iso.sha256"
rm -rf "$BASE/minichroot" "$BASE/audit" "$BASE/shots"/*.ppm
df -h / | tail -1

echo "=== 2) extract rootfs from squashfs ==="
if [ ! -d "$R/usr/bin" ]; then
  . "$BASE/tools-env.sh"
  rm -rf "$R"
  unsquashfs -q -d "$R" "$BASE/live/filesystem.squashfs" > /dev/null 2>&1
fi
test -d "$R/usr/bin" || { echo "EXTRACTION FAILED"; exit 1; }
echo "rootfs ready: $(du -sh "$R" | cut -f1)"

echo "=== 3) install persistence fixes ==="
install -m 755 "$S/fixed-initramfs-premount-bnasec-persist" "$R/etc/initramfs-tools/scripts/init-premount/bnasec-persist"
install -m 755 "$S/fixed-bnasec-persist-setup"          "$R/usr/local/sbin/bnasec-persist-setup"
install -m 755 "$S/fixed-hook-bnasec-persist-tools"     "$R/etc/initramfs-tools/hooks/bnasec-persist-tools"
# keep existing bnasec-udev-libs hook intact; verify key services still present
for f in "$R/etc/systemd/system/bnasec-persist.service" \
         "$R/etc/systemd/system/bnasec-firstboot.service" \
         "$R/etc/systemd/system/bnasec-persisttest.service" \
         "$R/usr/local/sbin/bnasec-firstboot" \
         "$R/usr/local/sbin/bnasec-persisttest" \
         "$R/usr/local/bin/wpscan"; do
  test -e "$f" || { echo "MISSING: $f"; exit 1; }
done
echo "fixes installed"

echo "=== 4) add fdisk package (sfdisk for fallback provisioning) ==="
FDEB="$BASE/debs/fdisk_2.41.5-0+deb13u1_amd64.deb"
mkdir -p "$BASE/debs"
if [ ! -f "$FDEB" ]; then
  curl -fsSL -o "$FDEB" "http://deb.debian.org/debian/pool/main/u/util-linux/fdisk_2.41.5-0+deb13u1_amd64.deb"
fi
. "$BASE/tools-env.sh"
dpkg-deb -x "$FDEB" "$R"
test -x "$R/usr/sbin/sfdisk" || { echo "sfdisk not installed from deb"; exit 1; }
echo "sfdisk installed: $($R/usr/sbin/sfdisk --version 2>&1 || echo ok)"

echo "=== 5) rebuild initramfs (chroot) ==="
KVER=$(ls "$R/lib/modules" | head -1)
echo "kernel: $KVER"
mkdir -p "$R/boot"
# kernel binary may have been excluded from squashfs (-e boot): restore from isostage
if [ ! -f "$R/boot/vmlinuz-$KVER" ]; then
  cp "$BASE/isostage/vmlinuz" "$R/boot/vmlinuz-$KVER"
fi
cd /home/z/my-project && . scripts/bnasec-chroot-env.sh
bnasec_run "mkinitramfs -o /boot/initrd.img-$KVER $KVER" 2>&1 | tail -3
test -s "$R/boot/initrd.img-$KVER" || { echo "initramfs FAILED"; exit 1; }
echo "initramfs rebuilt: $(du -h "$R/boot/initrd.img-$KVER" | cut -f1)"

echo "=== 6) verify new initramfs contents ==="
IRT=/tmp/initrd-verify
rm -rf "$IRT" && mkdir -p "$IRT"
CP=$BASE/tools-root/usr/bin/cpio
python3 - "$R/boot/initrd.img-$KVER" << 'PYEOF'
import sys, zstandard, io
data = open(sys.argv[1],'rb').read()
t = data.find(b'TRAILER!!!')          # end of prepended microcode cpio
i = data.find(b'\x28\xb5\x2f\xfd', t) # first zstd magic AFTER the microcode
assert i > 0, 'no zstd frame after microcode trailer'
with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(data[i:])) as r:
    out = r.read()
open('/tmp/main-verify.cpio','wb').write(out)
print('main archive:', round(len(out)/1048576), 'MB')
PYEOF
cd "$IRT" && $CP -idm --quiet < /tmp/main-verify.cpio 2>/dev/null || $CP -idm < /tmp/main-verify.cpio 2>&1 | tail -2
for f in scripts/init-premount/bnasec-persist usr/sbin/sfdisk usr/sbin/mke2fs \
         usr/lib/x86_64-linux-gnu/libfdisk.so.1 usr/lib/x86_64-linux-gnu/libreadline.so.8 \
         usr/lib/x86_64-linux-gnu/libext2fs.so.2 usr/share/plymouth/themes/bnasec/bnasec.plymouth; do
  test -e "$f" || { echo "INITRAMFS MISSING: $f"; exit 1; }
done
# blkid in either location
{ test -e usr/sbin/blkid || test -e usr/bin/blkid; } || { echo "INITRAMFS MISSING: blkid"; exit 1; }
echo "initramfs verification: ALL PRESENT"
# sfdisk must be able to load its libs inside the initramfs layout
LD_LIBRARY_PATH=$IRT/usr/lib/x86_64-linux-gnu:$IRT/lib/x86_64-linux-gnu $IRT/usr/sbin/sfdisk --version && echo "sfdisk loads OK"
LD_LIBRARY_PATH=$IRT/usr/lib/x86_64-linux-gnu:$IRT/lib/x86_64-linux-gnu $IRT/usr/sbin/partx --version 2>&1 | head -1
cd /tmp

echo "=== 7) rebuild squashfs ==="
bash "$S/bnasec-iso.sh" squashfs

echo "=== done — now run: bash scripts/bnasec-iso.sh iso ==="
