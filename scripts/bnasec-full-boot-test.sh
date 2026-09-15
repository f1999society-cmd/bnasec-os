#!/bin/bash
# Full boot test: BIOS, watch serial until GDM/desktop, take screenshots
set -e
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
. "$BASE/tools-env.sh"
Q="qemu-system-x86_64 -m 2048 -smp 2 -display none -usb -L $ROOT/usr/share/qemu -L $ROOT/usr/share/seabios -L $ROOT/usr/share/vgabios"
ISO=$BASE/bnasec-2.0.0-amd64.iso
S=$BASE/shots

rm -f $BASE/serial-biosfull.log
(sleep 25;  echo "screendump $S/full-t25.ppm"
 sleep 35;  echo "screendump $S/full-t60.ppm"
 sleep 60;  echo "screendump $S/full-t120.ppm"
 sleep 60;  echo "screendump $S/full-t180.ppm"
 sleep 60;  echo "screendump $S/full-t240.ppm"
 sleep 60;  echo "screendump $S/full-t300.ppm"
 sleep 30; echo quit) | \
  $Q -accel tcg,thread=multi -cdrom "$ISO" -monitor stdio \
     -serial file:$BASE/serial-biosfull.log 2>&1 | grep -viE "^\(qemu\)|audio" | head -3
for t in 25 60 120 180 240 300; do
  test -f $S/full-t$t.ppm && python3 -c "from PIL import Image; Image.open('$S/full-t$t.ppm').save('$S/full-t$t.png')" && echo "shot t$t"
done
echo "--- boot milestones ---"
grep -aE "Reached target|Started GDM|gdm|bnasec-persist|bnasec-firstboot|persistence" $BASE/serial-biosfull.log | tail -12
