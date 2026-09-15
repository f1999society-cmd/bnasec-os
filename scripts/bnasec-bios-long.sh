#!/bin/bash
# Extended BIOS boot test: multiple screendumps over 50s + serial capture
set -e
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
. "$BASE/tools-env.sh"
Q="qemu-system-x86_64 -m 2048 -smp 2 -display none -usb -L $ROOT/usr/share/qemu -L $ROOT/usr/share/seabios -L $ROOT/usr/share/vgabios"
ISO=$BASE/bnasec-2.0.0-amd64.iso
S=$BASE/shots

(sleep 18; echo "screendump $S/bios-t18.ppm"
 sleep 10; echo "screendump $S/bios-t28.ppm"
 sleep 15; echo "screendump $S/bios-t43.ppm"
 sleep 15; echo "screendump $S/bios-t58.ppm"
 sleep 5; echo quit) | \
  $Q -cdrom "$ISO" -monitor stdio -serial file:$BASE/serial-bios.log 2>&1 | grep -E "^$|error" | head -2
for t in 18 28 43 58; do
  python3 -c "from PIL import Image; Image.open('$S/bios-t$t.ppm').save('$S/bios-t$t.png')" 2>/dev/null && echo "shot t$t saved"
done
echo "--- serial log ---"; head -40 "$BASE/serial-bios.log" 2>/dev/null || echo "(serial empty)"
