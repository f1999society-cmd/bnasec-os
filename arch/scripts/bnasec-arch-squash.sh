#!/bin/bash
# BNAsec-Arch: build airootfs.sfs (zstd, all-root, bna ownership via pseudo file)
set -e
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS
SFS=$AB/airootfs.sfs

echo "=== pre-squash cleanup (runtime junk must not ship) ==="
rm -rf $R/run/* $R/tmp/* 2>/dev/null || true
rm -rf $R/var/lib/systemd/coredump 2>/dev/null || true
rm -rf $R/var/log/journal 2>/dev/null || true
find $R/var/log -type f -delete 2>/dev/null || true

echo "=== airootfs size ==="
du -sh $R || true

echo "=== generate pseudo file (bna = uid 1000 on /home/bna tree) ==="
PSEUDO=$AB/pseudo-home-bna.txt
: > $PSEUDO
( cd $R
  find home/bna | while read -r p; do
    mode=$(stat -c '%a' "$p")
    echo "/$p m $mode 1000 1000" >> $PSEUDO
  done
)
wc -l $PSEUDO

echo "=== mksquashfs (zstd-6, 1M blocks, all-root) ==="
rm -f $SFS
arch_run2 $ARCH_ROOT usr/bin/mksquashfs $R $SFS \
  -comp zstd -Xcompression-level 6 -b 1M \
  -all-root -noappend -pf $PSEUDO \
  -e var/cache/pacman/pkg 2>&1 | tail -4
ls -la $SFS
df -h / | tail -1
