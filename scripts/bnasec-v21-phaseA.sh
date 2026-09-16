#!/bin/bash
# BNAsec v2.1.0 Phase A: fetch v2.0.0 release ISO -> extract boot files + rootfs -> free space
set -e
BASE=/home/z/my-project/bnasec-build
TOKEN=$(cat /home/z/my-project/.gh-token)
REPO=f1999society-cmd/bnasec-os
. "$BASE/tools-env.sh"

echo "=== A1) locate ISO asset on release v2.0.0 ==="
AID=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/repos/$REPO/releases/tags/v2.0.0 | python3 -c "
import json,sys
r=json.load(sys.stdin)
for a in r['assets']:
    if a['name']=='bnasec-2.0.0-amd64.iso': print(a['id'])
")
echo "asset id: $AID"

echo "=== A2) download ISO (~1.5GB) ==="
LOC=$(curl -s -I -H "Authorization: token $TOKEN" -H "Accept: application/octet-stream" "https://api.github.com/repos/$REPO/releases/assets/$AID" | grep -i "^location:" | cut -d' ' -f2 | tr -d '\r')
curl -sL -o "$BASE/old.iso" "$LOC"
SZ=$(stat -c %s "$BASE/old.iso"); echo "downloaded: $SZ bytes"
[ "$SZ" -gt 1400000000 ] || { echo "download broken"; exit 1; }

echo "=== A3) sha256 (expect 03bdc98d...) ==="
sha256sum "$BASE/old.iso" | awk '{print "  actual:", $1}'

echo "=== A4) extract boot files + squashfs ==="
cd "$BASE"
xorriso -osirrox on -indev old.iso -extract /live/vmlinuz isostage/vmlinuz 2>&1 | tail -1
xorriso -osirrox on -indev old.iso -extract /live/initrd.img isostage/initrd.img 2>&1 | tail -1
xorriso -osirrox on -indev old.iso -extract /live/filesystem.squashfs old-fs.squashfs 2>&1 | tail -1
ls -la isostage/ | grep -E "vmlinuz|initrd"
ls -la old-fs.squashfs

echo "=== A5) free the ISO ==="
rm -f old.iso
df -h / | tail -1

echo "=== B2) extract rootfs ==="
rm -rf "$BASE/rootfs"
unsquashfs -q -d "$BASE/rootfs" old-fs.squashfs 2>&1 | tail -2
F1=$(find "$BASE/rootfs" -type f | wc -l); echo "rootfs files: $F1"
[ "$F1" -gt 100000 ] || { echo "extraction incomplete"; exit 1; }

echo "=== B3) free old squashfs ==="
rm -f old-fs.squashfs
df -h / | tail -1
echo "=== PHASE A DONE ==="
