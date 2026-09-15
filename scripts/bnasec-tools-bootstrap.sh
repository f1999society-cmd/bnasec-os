#!/bin/bash
# BNAsec toolchain bootstrap (sandbox-reset recovery): user-space tools via apt-get download + dpkg -x
set -e
BASE=/home/z/my-project/bnasec-build
mkdir -p "$BASE/debs" "$BASE/tools-root" "$BASE/assets" "$BASE/live" "$BASE/isostage"

# restore repo assets into expected locations
if [ -d /home/z/my-project/repo/bnasec-build/assets ]; then
  cp -a /home/z/my-project/repo/bnasec-build/assets/. "$BASE/assets/"
fi

cd "$BASE/debs"
PKGS="xorriso libisoburn1 libisofs6 libburn4 libjte2 libreadline8 libtinfo6 zlib1g \
squashfs-tools liblz4-1 liblzo2-2 libzstd1 liblzma5 \
grub-common grub-pc-bin grub-efi-amd64-bin mtools"

echo "=== 1) download debs ==="
for p in $PKGS; do
  if ! ls ${p}_*.deb >/dev/null 2>&1 && ! ls lib${p#lib}_*.deb >/dev/null 2>&1; then
    apt-get download "$p" 2>&1 | tail -1
  fi
done
ls *.deb | wc -l

echo "=== 2) extract into tools-root ==="
for d in *.deb; do dpkg -x "$d" "$BASE/tools-root/"; done

echo "=== 3) lean tools-env.sh ==="
cat > "$BASE/tools-env.sh" << 'EOF'
#!/bin/bash
export BNASEC_BASE=/home/z/my-project/bnasec-build
export ROOT=/home/z/my-project/bnasec-build/tools-root
export PATH="$ROOT/usr/bin:$ROOT/usr/sbin:$ROOT/sbin:$ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$ROOT/usr/lib/x86_64-linux-gnu:$ROOT/lib/x86_64-linux-gnu:$ROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
EOF

echo "=== 4) verify critical binaries ==="
. "$BASE/tools-env.sh"
xorriso -version 2>&1 | head -1
mksquashfs -version 2>&1 | head -1
unsquashfs -version 2>&1 | head -1
grub-mkimage --version 2>&1 | head -1
mformat --version 2>&1 | head -1
test -f "$ROOT/usr/lib/grub/i386-pc/boot_hybrid.img" && echo "  OK boot_hybrid.img"
test -d "$ROOT/usr/lib/grub/x86_64-efi" && echo "  OK x86_64-efi modules ($(ls $ROOT/usr/lib/grub/x86_64-efi | wc -l) files)"
test -f "$ROOT/usr/share/grub/unicode.pf2" && echo "  OK unicode.pf2"
test -f "$BASE/assets/iso-grub.cfg" && echo "  OK iso-grub.cfg"
echo "=== tools ready ==="
df -h / | tail -1
