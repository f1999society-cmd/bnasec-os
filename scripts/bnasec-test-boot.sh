#!/bin/bash
# QEMU boot tests for BNAsec ISO — foreground pipeline (monitor via stdio)
# usage: bash bnasec-test-boot.sh grub-bios | grub-uefi | persist:1|2|3 | gui-uefi
set -e
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
. "$BASE/tools-env.sh"
Q="qemu-system-x86_64 -m 2048 -smp 2 -display none -usb -L $ROOT/usr/share/qemu -L $ROOT/usr/share/seabios -L $ROOT/usr/share/vgabios"
ISO=$BASE/bnasec-2.0.0-amd64.iso
S=$BASE/shots

ppm2png() { /home/z/.venv/bin/python3 - "$1" "$2" <<'PYEOF'
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
PYEOF
}

case "$1" in
grub-bios)
  (sleep 10; echo "screendump $S/grub-bios.ppm"; sleep 2; echo quit) | \
    $Q -cdrom "$ISO" -monitor stdio -serial null 2>&1 | grep -E "screendump|mkimage|Keyboard" | head -2
  ppm2png "$S/grub-bios.ppm" "$S/grub-bios.png" && echo "grub-bios OK"
  ;;
grub-uefi)
  cp "$ROOT/usr/share/OVMF/OVMF_VARS_4M.fd" "$BASE/ovmf-vars.fd"
  (sleep 45; echo "screendump $S/grub-uefi.ppm"; sleep 2; echo quit) | \
    $Q -cdrom "$ISO" \
       -drive if=pflash,format=raw,readonly=on,file=$ROOT/usr/share/OVMF/OVMF_CODE_4M.fd \
       -drive if=pflash,format=raw,file=$BASE/ovmf-vars.fd \
       -monitor stdio -serial null 2>&1 | grep -E "screendump" | head -2
  ppm2png "$S/grub-uefi.ppm" "$S/grub-uefi.png" && echo "grub-uefi OK"
  ;;
persist:*)
  N=${1#persist:}
  USB=$BASE/test-usb.img
  if [ ! -f "$USB" ]; then
    qemu-img create -f raw "$USB" 8G >/dev/null
    dd if="$ISO" of="$USB" conv=notrunc bs=4M status=none
  fi
  (sleep 560; echo quit) | \
    $Q -accel tcg,thread=multi -no-reboot \
       -kernel "$BASE/isodir/live/vmlinuz" \
       -initrd "$BASE/isodir/live/initrd.img" \
       -append "boot=live persistence username=bna hostname=bnasec console=ttyS0 bnasec.persisttest" \
       -drive if=none,id=udisk,format=raw,file=$USB \
       -device usb-storage,drive=udisk \
       -serial file:$BASE/serial-boot$N.log \
       -monitor stdio 2>&1 | grep -E "qemu-system|reboot" | head -3 || true
  echo "--- serial boot$N (persist/persisttest lines) ---"
  grep -aE "bnasec-persist|overlay|persistence|firstboot|Z|multi-user|Reached" "$BASE/serial-boot$N.log" 2>/dev/null | tail -15
  ;;
gui-uefi)
  USB=$BASE/test-usb.img
  cp "$ROOT/usr/share/OVMF/OVMF_VARS_4M.fd" "$BASE/ovmf-vars2.fd"
  (sleep 60; echo "screendump $S/gui-1.ppm"; sleep 240; echo "screendump $S/gui-2.ppm"; sleep 150; echo "screendump $S/gui-3.ppm"; sleep 2; echo quit) | \
    $Q -accel tcg,thread=multi -L $ROOT/usr/share/qemu \
       -drive if=none,id=udisk,format=raw,file=$USB \
       -device usb-storage,drive=udisk \
       -drive if=pflash,format=raw,readonly=on,file=$ROOT/usr/share/OVMF/OVMF_CODE_4M.fd \
       -drive if=pflash,format=raw,file=$BASE/ovmf-vars2.fd \
       -monitor stdio -serial file:$BASE/serial-gui.log 2>&1 | grep -E "screendump" | head -4
  for i in 1 2 3; do ppm2png "$S/gui-$i.ppm" "$S/gui-$i.png"; done
  echo "gui test done"
  ;;

usb-bios)
  USB=$BASE/test-usb.img
  rm -f "$USB"
  qemu-img create -f raw "$USB" 8G >/dev/null
  dd if="$ISO" of="$USB" conv=notrunc bs=4M status=none
  (sleep 8; echo "screendump $S/usb-bios.ppm"; sleep 60; echo "screendump $S/usb-bios2.ppm"; sleep 2; echo quit) | \
    $Q -accel tcg,thread=multi \
       -drive if=none,id=udisk,format=raw,file=$USB \
       -device usb-storage,drive=udisk \
       -monitor stdio -serial file:$BASE/serial-usb-bios.log 2>&1 | grep -c screendump || true
  /home/z/.venv/bin/python3 - "$S/usb-bios.ppm" "$S/usb-bios.png" <<'PYEOF'
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
print("usb-bios OK")
import shutil; shutil.copy(sys.argv[1], sys.argv[1].replace(".ppm","2.ppm")); Image.open(sys.argv[1].replace(".ppm","2.ppm")).save(sys.argv[1].replace(".ppm","2.png"))
PYEOF
  ;;
usb-uefi)
  cp "$ROOT/usr/share/OVMF/OVMF_VARS_4M.fd" "$BASE/ovmf-vars3.fd"
  (sleep 40; echo "screendump $S/usb-uefi.ppm"; sleep 2; echo quit) | \
    $Q -accel tcg,thread=multi \
       -drive if=none,id=udisk,format=raw,file=$USB \
       -device usb-storage,drive=udisk \
       -drive if=pflash,format=raw,readonly=on,file=$ROOT/usr/share/OVMF/OVMF_CODE_4M.fd \
       -drive if=pflash,format=raw,file=$BASE/ovmf-vars3.fd \
       -monitor stdio -serial null 2>&1 | grep -c screendump || true
  /home/z/.venv/bin/python3 - "$S/usb-uefi.ppm" "$S/usb-uefi.png" <<'PYEOF'
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
print("usb-uefi OK")
PYEOF
  ;;
esac
