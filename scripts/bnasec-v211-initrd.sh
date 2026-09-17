#!/bin/bash
# BNAsec v2.1.1 — rebuild initramfs fix segment FROM CLEAN BACKUP (idempotent)
set -e
BASE=/home/z/my-project/bnasec-build
STG=/home/z/my-project/scripts/bnasec-v211-initrd
T=$BASE/tools-root/usr/bin
INITRD=$BASE/isostage/initrd.img

echo "=== 0) permissions + ORDER (sourced by run_scripts) ==="
chmod 755 $STG/scripts/init-bottom/99-bnasec-wallpaper $STG/bnasec-fix/bnasec-apply-wallpaper $STG/bnasec-fix/bnasec-demo 2>/dev/null
chmod 644 $STG/bnasec-fix/00-bnasec $STG/bnasec-fix/bnasec-wallpaper.desktop $STG/bnasec-fix/bnasec-demo.service 2>/dev/null
if ! grep -q "99-bnasec-wallpaper \"\$@\"" $STG/scripts/init-bottom/ORDER; then
  echo '/scripts/init-bottom/99-bnasec-wallpaper "$@"' >> $STG/scripts/init-bottom/ORDER
fi

echo "=== 1) restore clean initrd from backup ==="
[ -f /tmp/initrd.img.orig-210 ] || { echo "FATAL: backup missing"; exit 1; }
cp -f /tmp/initrd.img.orig-210 $INITRD

echo "=== 2) build append segment ==="
cd $STG
find . -print | LC_ALL=C sort | $T/cpio -o -H newc -R 0:0 2>/dev/null | gzip -9 > /tmp/bnasec-fix.cpio.gz
ls -la /tmp/bnasec-fix.cpio.gz
zcat /tmp/bnasec-fix.cpio.gz | $T/cpio -it 2>/dev/null

echo "=== 3) append ==="
cat /tmp/bnasec-fix.cpio.gz >> $INITRD
ls -la $INITRD

echo "=== 4) verify tail segment ==="
SZ=$(stat -c%s /tmp/bnasec-fix.cpio.gz)
tail -c $SZ $INITRD | zcat | $T/cpio -it 2>/dev/null | sort
echo "=== INITRD PATCHED (v2.1.1, from clean backup) ==="
