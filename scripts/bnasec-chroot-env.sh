#!/bin/bash
# Canonical shared env for all rootfs chroot operations (rootless fakechroot+fakeroot).
# Usage: cd /home/z/my-project && . scripts/bnasec-chroot-env.sh
BASE=/home/z/my-project/bnasec-build
export BASE
. "$BASE/tools-env.sh"

# fakechroot loader must also search rootfs multiarch dirs
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$BASE/rootfs/usr/lib/x86_64-linux-gnu:$BASE/rootfs/lib/x86_64-linux-gnu"

export FAKECHROOT_CMD_SUBST="/usr/sbin/ldconfig=$BASE/tools-root/usr/libexec/mmdebstrap/ldconfig.fakechroot:/sbin/ldconfig=$BASE/tools-root/usr/libexec/mmdebstrap/ldconfig.fakechroot:/usr/sbin/chroot=$BASE/tools-root/usr/sbin/chroot.fakechroot:/sbin/chroot=$BASE/tools-root/usr/sbin/chroot.fakechroot:/usr/bin/ldd=$BASE/tools-root/usr/bin/ldd.fakechroot:/bin/ldd=$BASE/tools-root/usr/bin/ldd.fakechroot:/bin/ischroot=/bin/true:/usr/bin/ischroot=/bin/true"
export FAKECHROOT_EXCLUDE_PATH="/dev:/proc:/sys"

bnasec_run() {
  fakechroot fakeroot chroot "$BASE/rootfs" /usr/bin/env \
    DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    LC_ALL=C HOME=/root bash -c "$1"
}
export -f bnasec_run

bnasec_min() {
  fakechroot fakeroot chroot "$BASE/minichroot" /usr/bin/env \
    DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root bash -c "$1"
}
export -f bnasec_min
