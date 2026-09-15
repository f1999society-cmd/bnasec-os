#!/bin/bash
# Stage A: bootstrap Debian trixie rootfs via mmdebstrap fakechroot mode (rootless)
set -e
BASE=/home/z/my-project/bnasec-build
. "$BASE/tools-env.sh"

if [ -f "$BASE/rootfs/usr/bin/dpkg" ]; then
  echo "rootfs already bootstrapped, skipping"
  exit 0
fi

rm -rf "$BASE/rootfs"
mkdir -p "$BASE/rootfs"
cd "$BASE"

mmdebstrap --mode=fakechroot --variant=apt --architectures=amd64 \
  --aptopt='Acquire::Languages none' \
  --aptopt='Acquire::Retries 3' \
  trixie "$BASE/rootfs" \
  "deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware"

echo "--- stage A done ---"
du -sh "$BASE/rootfs"
