#!/bin/bash
# BNAsec-Arch: build environment bootstrap (the missing piece — reconstructs
# everything env.sh expects after a sandbox reset).
#   1. compile symlink-shim.so
#   2. extract host tools: zstd, cpio  (Debian debs)
#   3. Arch bootstrap root -> $AB/arch-root (pacman + gpg + keyring)
#   4. pacman.conf -> $AB, empty-hooks dir, keyring trust init
#   5. build tools into arch-root: squashfs-tools grub libisoburn mtools
# Usage: bnasec-arch-env-setup.sh [qemu]     (add 'qemu' to also install QEMU)
set -e
REPO=/home/z/my-project/repo
export AB=/home/z/my-project/arch-build
export TOOLS=$AB/tools
mkdir -p $AB $TOOLS $AB/empty-hooks $AB/paccache

echo "=== 1) symlink-shim ==="
gcc -shared -fPIC -O2 -o $TOOLS/symlink-shim.so $REPO/arch/tools/symlink-shim.c -ldl
ls -la $TOOLS/symlink-shim.so

echo "=== 2) host tools: zstd + cpio (Debian debs) ==="
DL=$AB/debs; mkdir -p $DL; cd $DL
for p in zstd libzstd1 cpio; do apt-get download $p 2>/dev/null || apt-get download $p; done
for f in *.deb; do dpkg -x "$f" x/; done
mkdir -p $TOOLS/zstd-root $TOOLS/cpio-root
cp -a x/usr/. $TOOLS/zstd-root/usr/ 2>/dev/null || true
cp -a x/bin/. $TOOLS/zstd-root/usr/bin/ 2>/dev/null || true
cp -a x/usr/bin/. $TOOLS/zstd-root/usr/bin/ 2>/dev/null || true
$TOOLS/zstd-root/usr/bin/zstd --version 2>&1 | head -1
cp -a x/usr/bin/cpio $TOOLS/zstd-root/usr/bin/cpio 2>/dev/null || true
ls $TOOLS/zstd-root/usr/bin/ | head -5
# cpio needs its own lib closure check
ldd $TOOLS/zstd-root/usr/bin/cpio 2>/dev/null | grep "not found" && { echo "cpio libs missing"; exit 1; } || echo "cpio libs OK"

echo "=== 3) Arch bootstrap root ==="
cd $DL
if [ ! -x $AB/arch-root/usr/bin/pacman ]; then
  if [ ! -s bootstrap.tar.zst ] && [ ! -s bootstrap.tar ]; then
    curl -fL -o bootstrap.tar.zst "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.zst"
  fi
  ls -la bootstrap.tar.zst bootstrap.tar 2>/dev/null || true
  [ -s bootstrap.tar ] || $TOOLS/zstd-root/usr/bin/zstd -d -q -f bootstrap.tar.zst -o bootstrap.tar
  mkdir -p $AB/bsx
  # pass 1: some dirs in the tarball are mode 555 -> symlink creation fails
  env LD_PRELOAD=$TOOLS/symlink-shim.so tar -xf bootstrap.tar -C $AB/bsx 2>/dev/null || true
  # make everything writable, pass 2 fills the gaps (tar re-applies 555 dirs,
  # so the chmod MUST come after the final extraction)
  env LD_PRELOAD=$TOOLS/symlink-shim.so tar -xf bootstrap.tar -C $AB/bsx 2>/dev/null || true
  chmod -R u+w $AB/bsx 2>/dev/null || true
  rm -f bootstrap.tar.zst bootstrap.tar
  BSR=$(ls -d $AB/bsx/*/ | head -1)
  echo "bootstrap root: $BSR"
  mv "$BSR" $AB/arch-root
  rm -rf $AB/bsx
fi
ls $AB/arch-root/usr/bin/pacman && echo "pacman present"

echo "=== 4) pacman.conf + hooks + keyring ==="
cp $REPO/arch/tools/env.sh $AB/env.sh
mkdir -p $AB/scripts && cp $REPO/arch/scripts/* $AB/scripts/
cp $REPO/arch/tools/pacman.conf $AB/pacman.conf
chmod 700 $AB/arch-root/etc/pacman.d/gnupg 2>/dev/null || true
# keyring-init sources env.sh itself; invoke as a script:
bash $REPO/arch/scripts/bnasec-arch-keyring-init.sh $AB/arch-root/etc/pacman.d/gnupg

echo "=== 5) build tools into arch-root ==="
source $REPO/arch/tools/env.sh
pacman_b -Sy 2>&1 | tail -1
pacman_b -S --noconfirm --needed squashfs-tools grub libisoburn mtools 2>&1 | tail -2
for b in usr/bin/mksquashfs usr/bin/xorriso usr/bin/grub-mkimage usr/bin/mformat; do
  [ -x $AB/arch-root/$b ] && echo "  OK $b" || { echo "  MISSING $b"; exit 1; }
done

if [ "$1" = "qemu" ]; then
  echo "=== 6) QEMU (Debian debs) ==="
  cd $DL
  apt-get download qemu-system-x86 qemu-system-common qemu-system-data seabios ipxe-qemu vgabios ovmf 2>/dev/null
  # pull dependency closure of the qemu debs
  for f in qemu-system-x86_*.deb; do
    DEPS=$(dpkg-deb -f "$f" Depends | tr ',' '\n' | sed 's/ ([^)]*)//g; s/^ *//; s/ *$//' | grep -v '^$')
    for d in $DEPS; do apt-get download "$d" 2>/dev/null || true; done
  done
  mkdir -p $TOOLS/qemu-root
  for f in *.deb; do dpkg -x "$f" q/; done
  cp -a q/usr/. $TOOLS/qemu-root/usr/ 2>/dev/null || true
  cp -a q/lib/. $TOOLS/qemu-root/lib/ 2>/dev/null || true
  ls $TOOLS/qemu-root/usr/bin/qemu-system-x86_64 && echo "QEMU OK"
  ls $TOOLS/qemu-root/usr/share/ | head
fi

df -h / | tail -1
echo "ENV SETUP COMPLETE"
