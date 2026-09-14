#!/bin/bash
# Build the ISO-assembly minichroot (tiny trixie + grub + xorriso + mtools)
set -e
BASE=/home/z/my-project/bnasec-build
. "$BASE/tools-env.sh"

if [ -f "$BASE/minichroot/usr/bin/grub-mkrescue" ] && [ -f "$BASE/minichroot/usr/bin/xorriso" ]; then
  echo "minichroot ready"
  exit 0
fi

rm -rf "$BASE/minichroot"
mkdir -p "$BASE/minichroot"
mmdebstrap --mode=fakechroot --variant=minbase --architectures=amd64 \
  --aptopt='Acquire::Languages none' \
  trixie "$BASE/minichroot" \
  "deb http://deb.debian.org/debian trixie main" 2>&1 | tail -2

export FAKECHROOT_CMD_SUBST="/usr/sbin/ldconfig=$BASE/tools-root/usr/libexec/mmdebstrap/ldconfig.fakechroot:/sbin/ldconfig=$BASE/tools-root/usr/libexec/mmdebstrap/ldconfig.fakechroot:/usr/sbin/chroot=$BASE/tools-root/usr/sbin/chroot.fakechroot:/sbin/chroot=$BASE/tools-root/usr/sbin/chroot.fakechroot:/usr/bin/ldd=$BASE/tools-root/usr/bin/ldd.fakechroot:/bin/ldd=$BASE/tools-root/usr/bin/ldd.fakechroot:/bin/ischroot=/bin/true:/usr/bin/ischroot=/bin/true"
export FAKECHROOT_EXCLUDE_PATH="/dev:/proc:/sys"

fakechroot fakeroot chroot "$BASE/minichroot" /usr/bin/env \
  DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root bash -c \
  "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq grub-pc-bin grub-efi-amd64-bin xorriso mtools 2>&1 | tail -1; ls /usr/lib/grub/ | tr '\n' ' '; echo"
echo "--- minichroot built ---"
du -sh "$BASE/minichroot"
