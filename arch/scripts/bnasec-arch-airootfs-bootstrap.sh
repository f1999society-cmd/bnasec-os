#!/bin/bash
# BNAsec-Arch: bootstrap pacman+gpg into the EMPTY airootfs so pacman_ai works.
# Copies from the working arch-root: pacman/gpg binaries + their lib closures
# (ldd-driven) + the initialized keyring (489 ultimate-trust keys).
set -e
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS
S=$ARCH_ROOT

[ -x $S/usr/bin/pacman ] || { echo "FATAL: arch-root missing"; exit 1; }

echo "=== dirs ==="
mkdir -p $R/usr/bin $R/usr/lib $R/usr/share $R/var/lib/pacman/sync \
         $R/var/cache/pacman/pkg $R/var/log $R/etc/pacman.d

copy_bin() { # copy_bin <path-under-S> — binary + full ldd lib closure
  local src="$S/$1"
  [ -e "$src" ] || { echo "  skip $1 (absent)"; return 0; }
  local dst="$R/$1"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$src" ]; then cp -P "$src" "$dst"; return 0; fi
  cp -L "$src" "$dst"
  env LD_PRELOAD="$TOOLS/symlink-shim.so" "$S/lib64/ld-linux-x86-64.so.2" \
      --library-path "$S/usr/lib:$S/usr/lib/systemd:$S/lib" \
      --list "$src" 2>/dev/null | awk '/=> \//{print $3}' | grep -E '^/' | sort -u | \
  while read -r lib; do
    local rel="${lib#$S/}"
    [ "$rel" = "$lib" ] && continue
    [ -e "$R/$rel" ] && continue
    mkdir -p "$(dirname "$R/$rel")"
    cp -L "$lib" "$R/$rel" 2>/dev/null || true
  done
}

echo "=== loader + glibc ==="
cp -L $S/usr/lib/ld-linux-x86-64.so.2 $R/usr/lib/ 2>/dev/null || \
  cp -L $S/lib/ld-linux-x86-64.so.2 $R/usr/lib/
cp -L $S/usr/lib/libc.so.6 $R/usr/lib/
mkdir -p $R/lib64
[ -e $R/lib64/ld-linux-x86-64.so.2 ] || ln -sf ../usr/lib/ld-linux-x86-64.so.2 $R/lib64/ld-linux-x86-64.so.2

echo "=== pacman + gpg family ==="
for b in pacman gpg gpgv gpgconf gpgsm gpg-agent dirmngr gpg-connect-agent; do
  copy_bin usr/bin/$b
done

echo "=== keyring (initialized, 489 keys) ==="
rm -rf $R/etc/pacman.d/gnupg
cp -a $S/etc/pacman.d/gnupg $R/etc/pacman.d/gnupg
chmod -R u+rw $R/etc/pacman.d/gnupg
ls $R/etc/pacman.d/gnupg/ | head -4

echo "=== pacman support files ==="
cp -a $S/usr/share/pacman $R/usr/share/ 2>/dev/null || true
cp -a $S/usr/bin/pacman-key $R/usr/bin/ 2>/dev/null || true
cp -a $S/usr/bin/pacman-conf $R/usr/bin/ 2>/dev/null || true

echo "=== smoke test: pacman version ==="
arch_run2 $R usr/bin/pacman --version | head -2 || { echo "FATAL: pacman won't run"; exit 1; }
echo "AIROOTFS BOOTSTRAP COMPLETE"
du -sh $R
