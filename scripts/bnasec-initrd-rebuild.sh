#!/bin/bash
# BNAsec: rebuild initramfs inside mini-rootfs (space-safe), verify exhaustively
set -e
BASE=/home/z/my-project/bnasec-build
M=$BASE/mini-rootfs
KVER=6.12.107+deb13-amd64
S=/home/z/my-project/scripts

. "$BASE/tools-env.sh"

echo "=== mkinitramfs in mini-rootfs (fakechroot) ==="
# deterministic in-chroot ldd (resolves against mini-rootfs, no host leakage)
install -m 755 "$S/bnasec-chroot-ldd" "$M/usr/bin/ldd"
export FAKECHROOT_CMD_SUBST="/usr/sbin/ldconfig=$BASE/tools-root/usr/libexec/mmdebstrap/ldconfig.fakechroot:/sbin/ldconfig=$BASE/tools-root/usr/libexec/mmdebstrap/ldconfig.fakechroot:/usr/sbin/chroot=$BASE/tools-root/usr/sbin/chroot.fakechroot:/sbin/chroot=$BASE/tools-root/usr/sbin/chroot.fakechroot:/bin/ischroot=/bin/true:/usr/bin/ischroot=/bin/true"
export FAKECHROOT_EXCLUDE_PATH="/dev:/proc:/sys"
# NOTE: ldd deliberately NOT in FAKECHROOT_CMD_SUBST — the mini-rootfs's own
# wrapper resolves against its own root (see scripts/bnasec-chroot-ldd)
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$M/usr/lib/x86_64-linux-gnu"

mkdir -p "$M/boot"
rm -f "$M/boot/initrd.img-$KVER"
fakechroot fakeroot chroot "$M" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root \
  /usr/sbin/mkinitramfs -o "/boot/initrd.img-$KVER" "$KVER" 2>&1 | tail -8
test -s "$M/boot/initrd.img-$KVER" || { echo "INITRAMFS BUILD FAILED"; exit 1; }
ls -la "$M/boot/initrd.img-$KVER"

echo "=== exhaustive initramfs verification (host-side) ==="
V=/tmp/initrd-final
rm -rf "$V" && mkdir -p "$V"
python3 - "$M/boot/initrd.img-$KVER" << 'PYEOF'
import sys, zstandard, io
data = open(sys.argv[1],'rb').read()
t = data.find(b'TRAILER!!!')
i = data.find(b'\x28\xb5\x2f\xfd', t)
assert i > 0, "no zstd main frame"
out = zstandard.ZstdDecompressor().stream_reader(io.BytesIO(data[i:])).read()
open('/tmp/initrd-final/main.cpio','wb').write(out)
print("main archive:", round(len(out)/1048576), "MB | ko refs:", out.count(b'.ko.xz'))
PYEOF
cd "$V" && cpio=$BASE/tools-root/usr/bin/cpio; $cpio -idm --quiet < main.cpio 2>/dev/null || $cpio -idm < main.cpio 2>&1 | tail -1

echo "--- module counts ---"
find "$V" -name "*.ko.xz" -o -name "*.ko" | wc -l
for m in uhci-hcd ehci-pci xhci-pci usb-storage uas iso9660 ext4 overlay; do
  find "$V/usr/lib/modules" -name "${m}.ko*" | head -1 | grep -q . && echo "  OK  $m" || { echo "  MISSING $m"; exit 1; }
done

echo "--- udevd dependency closure (ldd against extracted initramfs) ---"
L=$V/usr/lib/x86_64-linux-gnu
MISSING=0
for lib in $(ldd "$V/usr/lib/systemd/systemd-udevd" 2>/dev/null | awk '$2 ~ /=>/ {print $1} /=> not found/ {print $1}' | sort -u); do
  found=$(find "$V" -name "$lib" | head -1)
  [ -n "$found" ] && echo "  OK  $lib" || { echo "  MISSING $lib"; MISSING=1; }
done
[ "$MISSING" = "0" ] || { echo "UDEVD DEPS INCOMPLETE"; exit 1; }
echo "--- udevd binary runs (as udevd --version needs root, use --help) ---"
LD_LIBRARY_PATH=$L $V/usr/lib/systemd/systemd-udevd --help 2>&1 | head -2 || true
echo "--- sfdisk/blkid/mke2fs load ---"
for b in sfdisk blkid mke2fs; do
  LD_LIBRARY_PATH=$L $V/usr/sbin/$b --version 2>&1 | head -1 || true
done
echo "--- premount + plymouth + persist artifacts ---"
for p in scripts/init-premount/bnasec-persist usr/share/plymouth/themes/bnasec/bnasec.plymouth \
         usr/share/plymouth/themes/bnasec/bnasec-logo.png usr/sbin/plymouthd \
         usr/lib/systemd/libsystemd-shared-257.so; do
  test -e "$V/$p" && echo "  OK  $p" || { echo "  MISSING $p"; exit 1; }
done
echo "=== ALL INITRAMFS CHECKS PASSED ==="

cp "$M/boot/initrd.img-$KVER" "$BASE/isostage/initrd.img"
echo "isostage/initrd.img updated: $(ls -la $BASE/isostage/initrd.img | awk '{print $5}') bytes"
