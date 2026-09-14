#!/bin/bash
# Patch toolchain files with hardcoded paths so they work rootless from tools-root
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/tools-root

# 1) fakeroot: dpkg -x creates no alternatives symlinks
ln -sf fakeroot-sysv "$R/usr/bin/fakeroot"

# 2) fakeroot-sysv: hardcoded PATHS/PREFIX/BINDIR point to /usr
sed -i "s|^PATHS=.*|PATHS=\"$R/usr/lib/x86_64-linux-gnu/libfakeroot\"|" "$R/usr/bin/fakeroot-sysv"
sed -i "s|^FAKEROOT_PREFIX=.*|FAKEROOT_PREFIX=\"$R\"|" "$R/usr/bin/fakeroot-sysv"
sed -i "s|^FAKEROOT_BINDIR=.*|FAKEROOT_BINDIR=\"$R/usr/bin\"|" "$R/usr/bin/fakeroot-sysv"

# 3) mmdebstrap: fakechroot subst map entries point into tools-root
sed -i "s|/usr/sbin/chroot\.fakechroot|$R/usr/sbin/chroot.fakechroot|g" "$R/usr/bin/mmdebstrap"
sed -i "s|/usr/libexec/mmdebstrap/ldd\.fakechroot|$R/usr/libexec/mmdebstrap/ldd.fakechroot|g" "$R/usr/bin/mmdebstrap"
sed -i "s|/usr/libexec/mmdebstrap/ldconfig\.fakechroot|$R/usr/libexec/mmdebstrap/ldconfig.fakechroot|g" "$R/usr/bin/mmdebstrap"

echo "--- verification ---"
ls -la "$R/usr/bin/fakeroot" | head -1
grep -c "$R/usr/libexec/mmdebstrap" "$R/usr/bin/mmdebstrap" || true
grep "^PATHS=" "$R/usr/bin/fakeroot-sysv"
echo "patch done"
