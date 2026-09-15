#!/bin/bash
# Final UEFI verification: boot the FIXED final ISO (15:51 build) under OVMF
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
S=$BASE/shots
. "$BASE/tools-env.sh"
rm -f $BASE/serial-uefi.log $S/uefi-t*.ppm $S/uefi-t*.png
cp "$ROOT/usr/share/OVMF/OVMF_VARS_4M.fd" "$BASE/ovmf-vars.fd"
Q="qemu-system-x86_64 -m 2048 -smp 2 -display none -usb -L $ROOT/usr/share/qemu -L $ROOT/usr/share/seabios -L $ROOT/usr/share/vgabios"
(sleep 75;   echo "screendump $S/uefi-t75.ppm"
 sleep 45;  echo "screendump $S/uefi-t120.ppm"
 sleep 60;  echo "screendump $S/uefi-t180.ppm"
 sleep 60;  echo "screendump $S/uefi-t240.ppm"
 sleep 60;  echo "screendump $S/uefi-t300.ppm"
 sleep 5; echo quit) | \
  $Q -accel tcg,thread=multi -cdrom "$BASE/bnasec-2.0.0-amd64.iso" -monitor stdio \
     -drive if=pflash,format=raw,readonly=on,file=$ROOT/usr/share/OVMF/OVMF_CODE_4M.fd \
     -drive if=pflash,format=raw,file=$BASE/ovmf-vars.fd \
     -serial file:$BASE/serial-uefi.log 2>&1 | grep -viE "^\(qemu\)|audio" | head -3
for t in 75 120 180 240 300; do
  test -f $S/uefi-t$t.ppm && /home/z/.venv/bin/python3 -c "from PIL import Image; Image.open('$S/uefi-t$t.ppm').save('$S/uefi-t$t.png')" && echo "t$t saved"
done
echo "--- screenshots captured ---"
ls -la $S/uefi-t*.png 2>/dev/null
