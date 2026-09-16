#!/bin/bash
# BNAsec FINAL REBUILD: checkpoint(GitHub) -> verified rootfs -> initrd -> squashfs
# Everything explicit, verified, space-budgeted. ISO built separately.
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
S=/home/z/my-project/scripts
KVER=6.12.107+deb13-amd64
TOKEN=$(cat /home/z/my-project/.gh-token)

df -h / | tail -1

echo "=== 1) free space: drop partial artifacts ==="
rm -rf "$BASE/mini-rootfs" "$BASE/live/filesystem.squashfs" /tmp/sq-from-iso
df -h / | tail -1

echo "=== 2) fetch checkpoint (GitHub release, verified size) ==="
CKPT="$BASE/checkpoint.squashfs"
if [ ! -f "$CKPT" ]; then
  AID=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/repos/f1999society-cmd/bnasec-os/releases/tags/checkpoint | python3 -c "import json,sys;print(json.load(sys.stdin)['assets'][0]['id'])")
  SIGNED=$(curl -s -I -H "Authorization: token $TOKEN" -H "Accept: application/octet-stream" "https://api.github.com/repos/f1999society-cmd/bnasec-os/releases/assets/$AID" | grep -i "^location:" | cut -d' ' -f2 | tr -d '\r')
  curl -sL -o "$CKPT" "$SIGNED"
fi
SZ=$(stat -c %s "$CKPT")
echo "checkpoint: $SZ bytes"
[ "$SZ" -gt 1400000000 ] || { echo "checkpoint too small — download broken"; exit 1; }

echo "=== 3) extract rootfs (VERBOSE — no silent truncation!) ==="
rm -rf "$R"
. "$BASE/tools-env.sh"
unsquashfs -q -d "$R" "$CKPT" 2>&1 | tail -3
F1=$(find "$R" -type f | wc -l)
echo "rootfs files: $F1"
[ "$F1" -gt 100000 ] || { echo "rootfs extraction looks incomplete"; exit 1; }
rm -f "$CKPT"
df -h / | tail -1

echo "=== 4) sanity-check previously-missing files ==="
for f in usr/lib/klibc/bin/cat usr/lib/klibc-*.so usr/sbin/losetup usr/lib/x86_64-linux-gnu/libkmod.so.2 \
         usr/bin/iucode_tool usr/share/initramfs-tools/hook-functions usr/bin/zstd usr/bin/objdump; do
  ls $R/$f > /dev/null 2>&1 && echo "  OK  $f" || echo "  MISS $f"
done

echo "=== 5) install persistence fixes ==="
install -m 755 "$S/fixed-initramfs-premount-bnasec-persist" "$R/etc/initramfs-tools/scripts/init-premount/bnasec-persist"
install -m 755 "$S/fixed-bnasec-persist-setup"          "$R/usr/local/sbin/bnasec-persist-setup"
rm -f  "$R/etc/initramfs-tools/hooks/bnasec-udev-libs"
install -m 755 "$S/fixed-hook-bnasec-persist-tools"     "$R/etc/initramfs-tools/hooks/bnasec-persist-tools"
install -m 755 "$S/fixed-hook-bnasec-udev-complete"     "$R/etc/initramfs-tools/hooks/bnasec-udev-complete"
install -m 755 "$S/fixed-hook-bnasec-plymouth-complete" "$R/etc/initramfs-tools/hooks/bnasec-plymouth-complete"
rm -f "$R/usr/share/initramfs-tools/hooks/kmod" "$R/usr/share/initramfs-tools/hooks/zz-busybox"
install -m 755 "$S/fixed-hook-kmod-explicit"   "$R/usr/share/initramfs-tools/hooks/kmod-explicit"
install -m 755 "$S/fixed-hook-zz-busybox"      "$R/usr/share/initramfs-tools/hooks/zz-busybox"
rm -f "$R/usr/share/initramfs-tools/hooks/intel_microcode"
# deterministic ldd: patch hook-functions + install the wrapper
install -m 755 "$S/bnasec-chroot-ldd" "$R/usr/local/bin/bnasec-ldd"
sed -i 's|env --unset=LD_PRELOAD ldd |/usr/local/bin/bnasec-ldd |g' "$R/usr/share/initramfs-tools/hook-functions"
mkdir -p "$R/boot" "$R/var/tmp" "$R/tmp"
# fdisk package (sfdisk for the systemd fallback provisioner)
FDEB="$BASE/debs/fdisk_2.41.5-0+deb13u1_amd64.deb"
mkdir -p "$BASE/debs"
[ -f "$FDEB" ] || curl -fsSL -o "$FDEB" "http://deb.debian.org/debian/pool/main/u/util-linux/fdisk_2.41.5-0+deb13u1_amd64.deb"
dpkg-deb -x "$FDEB" "$R"
test -x "$R/usr/sbin/sfdisk" && echo "  sfdisk installed"
# kernel from isostage
cp "$BASE/isostage/vmlinuz" "$R/boot/vmlinuz-$KVER"

echo "=== 6) mkinitramfs ==="
cd /home/z/my-project && . scripts/bnasec-chroot-env.sh
rm -f "$R/boot/initrd.img-$KVER"
bnasec_run "mkinitramfs -o /boot/initrd.img-$KVER $KVER" 2>&1 | tail -5
test -s "$R/boot/initrd.img-$KVER" || { echo "INITRAMFS FAILED"; exit 1; }

echo "=== 7) verify initramfs exhaustively ==="
V=/tmp/initrd-final; rm -rf "$V"; mkdir -p "$V"
python3 - "$R/boot/initrd.img-$KVER" << 'PYEOF'
import sys, zstandard, io
data = open(sys.argv[1],'rb').read()
t = data.find(b'TRAILER!!!'); i = data.find(b'\x28\xb5\x2f\xfd', t)
assert i > 0, "no zstd frame"
out = zstandard.ZstdDecompressor().stream_reader(io.BytesIO(data[i:])).read()
open('/tmp/initrd-final/main.cpio','wb').write(out)
print("main:", round(len(out)/1048576), "MB | ko refs:", out.count(b'.ko.xz'))
PYEOF
cd "$V" && $BASE/tools-root/usr/bin/cpio -idm --quiet < main.cpio 2>/dev/null
NM=$(find "$V" -name "*.ko.xz" -o -name "*.ko" | wc -l); echo "modules: $NM"
[ "$NM" -gt 3000 ] || { echo "TOO FEW MODULES"; exit 1; }
for m in uhci-hcd ehci-pci xhci-pci usb-storage uas iso9660 ext4 overlay; do
  find "$V/usr/lib/modules" -name "${m}.ko*" | grep -q . && echo "  OK  $m" || { echo "  MISSING $m"; exit 1; }
done
MISSING=0
for lib in $(ldd "$V/usr/bin/udevadm" 2>/dev/null | awk '/=> \//{print $1}'); do
  find "$V" -name "$lib" | grep -q . || { echo "  udevd lib MISSING: $lib"; MISSING=1; }
done
[ "$MISSING" = "0" ] || exit 1
for p in scripts/init-premount/bnasec-persist usr/share/plymouth/themes/bnasec/bnasec.plymouth \
         usr/sbin/plymouthd bin/busybox usr/lib/systemd/libsystemd-shared-257.so usr/lib/udev/rules.d; do
  test -e "$V/$p" && echo "  OK  $p" || { echo "  MISSING $p"; exit 1; }
done
echo "=== INITRAMFS VERIFIED ==="

cp "$R/boot/initrd.img-$KVER" "$BASE/isostage/initrd.img"

echo "=== 8) rebuild squashfs ==="
mkdir -p "$BASE/live"
mksquashfs "$R" "$BASE/live/filesystem.squashfs" \
  -comp zstd -Xcompression-level 6 -b 1M -all-root -noappend \
  -e boot -wildcards -e 'var/cache/apt/*' 'var/lib/apt/lists/*' 2>&1 | tail -1
ls -la "$BASE/live/"

echo "=== done — run bnasec-hybrid-iso.sh next ==="
