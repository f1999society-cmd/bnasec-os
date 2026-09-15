#!/bin/bash
# Debug boot: direct kernel + initrd, serial console, watch init fail live
set -e
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
. "$BASE/tools-env.sh"
Q="qemu-system-x86_64 -m 2048 -smp 2 -display none -usb -L $ROOT/usr/share/qemu -L $ROOT/usr/share/seabios -L $ROOT/usr/share/vgabios"
ISO=$BASE/bnasec-2.0.0-amd64.iso

(sleep 90; echo quit) | \
  $Q -accel tcg,thread=multi -no-reboot \
     -kernel "$BASE/isostage/vmlinuz" \
     -initrd "$BASE/isostage/initrd.img" \
     -append "boot=live persistence username=bna hostname=bnasec console=ttyS0 debug" \
     -cdrom "$ISO" \
     -serial file:$BASE/serial-debug.log \
     -monitor stdio 2>&1 | grep -viE "^\(qemu\)|audio" | head -3 || true
echo "=== serial log (last 50) ==="
tail -50 "$BASE/serial-debug.log"
