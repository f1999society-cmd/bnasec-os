#!/bin/bash
# BNAsec v2.1.0 toolchain bootstrap (sandbox-reset recovery)
# User-space build toolchain: xorriso/squashfs/grub/mtools/cpio/fakechroot + qemu for tests
# trixie t64 gotcha: libisoburn1->libisoburn1t64, libisofs6->libisofs6t64, libburn4->libburn4t64
set -e
BASE=/home/z/my-project/bnasec-build
mkdir -p "$BASE/debs" "$BASE/tools-root" "$BASE/assets" "$BASE/live" "$BASE/isostage" "$BASE/shots"

# restore repo assets into expected locations
if [ -d /home/z/my-project/repo/bnasec-build/assets ]; then
  cp -a /home/z/my-project/repo/bnasec-build/assets/. "$BASE/assets/"
fi

cd "$BASE/debs"
PKGS="xorriso libisoburn1t64 libisofs6t64 libburn4t64 libjte2 libreadline8 libtinfo6 zlib1g \
squashfs-tools liblz4-1 liblzo2-2 libzstd1 liblzma5 zstd \
grub-common grub-pc-bin grub-efi-amd64-bin mtools cpio \
fakechroot fakeroot libfakeroot \
qemu-system-x86 qemu-system-common qemu-system-data seabios vgabios \
libglib2.0-0t64 libpixman-1-0 libslirp0 liburing2 libaio1t64 libfdt1 \
libcapstone4 libgcrypt20 libgnutls30 libnettle8 libhogweed6 libgmp10 \
libusb-1.0-0 libseccomp2 libzstd1 libnuma1 libfuse3-3 libcap2"

echo "=== 1) download debs ==="
for p in $PKGS; do
  if ! ls ${p}_*.deb >/dev/null 2>&1; then
    apt-get download "$p" 2>&1 | tail -1
  fi
done
ls *.deb | wc -l

echo "=== 2) extract into tools-root ==="
for d in *.deb; do dpkg -x "$d" "$BASE/tools-root/"; done

echo "=== 3) rich tools-env.sh (fakechroot-aware, matches repo copy) ==="
cat > "$BASE/tools-env.sh" << 'EOF'
#!/bin/bash
# auto-generated — host-side rootless build toolchain
export BNASEC_BASE=/home/z/my-project/bnasec-build
export ROOT=/home/z/my-project/bnasec-build/tools-root
export PATH="$ROOT/usr/bin:$ROOT/usr/sbin:$ROOT/sbin:$ROOT/bin:$ROOT/usr/lib/llvm-19/bin:$PATH"
export LD_LIBRARY_PATH="$ROOT/usr/lib/x86_64-linux-gnu/fakechroot:$ROOT/usr/lib/x86_64-linux-gnu/libfakeroot:$ROOT/usr/lib/x86_64-linux-gnu:$ROOT/lib/x86_64-linux-gnu:$ROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PERL5LIB="$ROOT/usr/share/perl5:$ROOT/usr/share/perl5/vendor_perl:$ROOT/usr/lib/x86_64-linux-gnu/perl5/5.40 $ROOT/usr/lib/x86_64-linux-gnu/perl5/5.38 $ROOT/usr/lib/x86_64-linux-gnu/perl5/5.36:$ROOT/usr/lib/x86_64-linux-gnu/perl-base${PERL5LIB:+:$PERL5LIB}"
export PYTHONPATH="$ROOT/usr/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
export GIO_MODULE_DIR="$ROOT/usr/lib/x86_64-linux-gnu/gio/modules"
EOF

echo "=== 4) verify critical binaries ==="
. "$BASE/tools-env.sh"
xorriso -version 2>&1 | head -1
mksquashfs -version 2>&1 | head -1
unsquashfs -version 2>&1 | head -1
grub-mkimage --version 2>&1 | head -1
mformat --version 2>&1 | head -1
cpio --version 2>&1 | head -1
zstd --version 2>&1 | head -1
test -x "$ROOT/usr/bin/qemu-system-x86_64" && echo "  OK qemu-system-x86_64"
test -f "$ROOT/usr/lib/grub/i386-pc/boot_hybrid.img" && echo "  OK boot_hybrid.img"
test -d "$ROOT/usr/lib/grub/x86_64-efi" && echo "  OK x86_64-efi modules ($(ls $ROOT/usr/lib/grub/x86_64-efi | wc -l) files)"
test -f "$ROOT/usr/share/grub/unicode.pf2" && echo "  OK unicode.pf2"
test -f "$BASE/assets/iso-grub.cfg" && echo "  OK iso-grub.cfg"

echo "=== 5) qemu dependency check (ldd against tools-root) ==="
MISS=0
for lib in $(ldd "$ROOT/usr/bin/qemu-system-x86_64" 2>/dev/null | awk '$2 ~ /=>/ {print $1} /=> not found/ {print $1}' | sort -u); do
  if find "$ROOT" -name "$lib" | grep -q .; then echo "  OK  $lib"; else echo "  MISSING $lib"; MISS=1; fi
done
# qemu data dirs for -L
for d in usr/share/qemu usr/share/seabios usr/share/vgabios; do
  test -d "$ROOT/$d" && echo "  OK  $ROOT/$d" || echo "  MISS-DIR $d"
done
[ "$MISS" = 0 ] || echo "NOTE: some qemu libs missing — resolve with pool fetch"
echo "=== tools ready ==="
df -h / | tail -1
