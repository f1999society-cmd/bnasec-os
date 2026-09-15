#!/bin/bash
# BIOS smoke test for the suid-fixed ISO: boot CD-ROM -> expect GDM desktop
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
S=$BASE/shots
. "$BASE/tools-env.sh"
rm -f $BASE/serial-smoke.log $S/smoke-t*.ppm $S/smoke-t*.png
Q="qemu-system-x86_64 -m 2048 -smp 2 -display none -usb -L $ROOT/usr/share/qemu -L $ROOT/usr/share/seabios -L $ROOT/usr/share/vgabios"
(sleep 75;   echo "screendump $S/smoke-t75.ppm"
 sleep 45;  echo "screendump $S/smoke-t120.ppm"
 sleep 60;  echo "screendump $S/smoke-t180.ppm"
 sleep 60;  echo "screendump $S/smoke-t240.ppm"
 sleep 60;  echo "screendump $S/smoke-t300.ppm"
 sleep 5; echo quit) | \
  $Q -accel tcg,thread=multi -cdrom "$BASE/bnasec-2.0.0-amd64.iso" -monitor stdio \
     -serial file:$BASE/serial-smoke.log 2>&1 | grep -viE "^\(qemu\)|audio" | head -3
for t in 75 120 180 240 300; do
  test -f $S/smoke-t$t.ppm && /home/z/.venv/bin/python3 -c "from PIL import Image; Image.open('$S/smoke-t$t.ppm').save('$S/smoke-t$t.png')" && echo "t$t saved"
done
echo "--- serial milestones ---"
grep -aE "Reached target|Started GDM|bnasec-suid|bnasec-firstboot" $BASE/serial-smoke.log | tail -8
