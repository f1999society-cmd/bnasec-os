#!/bin/bash
# Extended UEFI test: OVMF needs longer under TCG
set -e
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
. "$BASE/tools-env.sh"
Q="qemu-system-x86_64 -m 2048 -smp 2 -display none -usb -L $ROOT/usr/share/qemu -L $ROOT/usr/share/seabios -L $ROOT/usr/share/vgabios"
ISO=$BASE/bnasec-2.0.0-amd64.iso
S=$BASE/shots
cp "$ROOT/usr/share/OVMF/OVMF_VARS_4M.fd" "$BASE/ovmf-vars.fd"
(sleep 60;  echo "screendump $S/uefi-t60.ppm"
 sleep 45;  echo "screendump $S/uefi-t105.ppm"
 sleep 45;  echo "screendump $S/uefi-t150.ppm"
 sleep 60;  echo "screendump $S/uefi-t210.ppm"
 sleep 5; echo quit) | \
  $Q -accel tcg,thread=multi -cdrom "$ISO" -monitor stdio \
     -drive if=pflash,format=raw,readonly=on,file=$ROOT/usr/share/OVMF/OVMF_CODE_4M.fd \
     -drive if=pflash,format=raw,file=$BASE/ovmf-vars.fd \
     -serial file:$BASE/serial-uefi.log 2>&1 | grep -viE "^\(qemu\)|audio" | head -3
for t in 60 105 150 210; do
  test -f $S/uefi-t$t.ppm && /home/z/.venv/bin/python3 -c "from PIL import Image; Image.open('$S/uefi-t$t.ppm').save('$S/uefi-t$t.png')" && echo "t$t saved"
done
echo "--- OVMF serial (last lines) ---"
tail -20 "$BASE/serial-uefi.log" 2>/dev/null | head -20
