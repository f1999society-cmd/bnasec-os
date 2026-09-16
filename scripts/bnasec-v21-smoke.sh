#!/bin/bash
# BNAsec v2.1.0 BIOS smoke test: boot CD -> expect plymouth splash -> GDM LOGIN (no autologin!)
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
S=$BASE/shots
. "$BASE/tools-env.sh"
rm -f $BASE/serial-smoke21.log $S/s21-*.ppm $S/s21-*.png
Q="qemu-system-x86_64 -m 2048 -smp 2 -display none -usb -nic none -L $ROOT/usr/share/qemu -L $ROOT/usr/share/seabios -L $ROOT/usr/share/vgabios"
(sleep 30;   echo "screendump $S/s21-t30.ppm"    # plymouth splash window
 sleep 45;  echo "screendump $S/s21-t75.ppm"    # late plymouth or early GDM
 sleep 45;  echo "screendump $S/s21-t120.ppm"   # GDM login expected
 sleep 60;  echo "screendump $S/s21-t180.ppm"   # still login (no autologin!)
 sleep 60;  echo "screendump $S/s21-t240.ppm"
 sleep 30; echo quit) | \
  $Q -accel tcg,thread=multi -cdrom "$BASE/bnasec-2.1.0-amd64.iso" -monitor stdio \
     -serial file:$BASE/serial-smoke21.log 2>&1 | grep -viE "^\(qemu\)|audio" | head -3
for t in 30 75 120 180 240; do
  test -f $S/s21-t$t.ppm && /home/z/.venv/bin/python3 -c "from PIL import Image; Image.open('$S/s21-t$t.ppm').save('$S/s21-t$t.png')" && echo "t$t saved"
done
echo "--- serial milestones ---"
grep -aE "Reached target|Started GDM|bnasec|zram|live-config|systemd" $BASE/serial-smoke21.log | tail -12 || true
echo "--- done ---"
