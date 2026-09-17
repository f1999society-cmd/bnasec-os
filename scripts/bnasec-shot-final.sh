#!/bin/bash
# Final captures: (1) themed GRUB menu, (2) Firefox window via alt-tab cycling
set -u
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
PY=/home/z/.venv/bin/python3
SESS=/home/z/my-project/scripts/bnasec-sess.py
SOCK=/tmp/bna-sess.sock
. "$BASE/tools-env.sh"
export BNA_SERIAL_LOG="$BASE/serial-sess-final.log"
rm -f "$SOCK" "$BASE/serial-sess-final.log" "$BASE/beacon-F.log"

echo "=== 1) GRUB menu capture (normal BIOS boot, no keypress) ==="
qemu-system-x86_64 -m 1024 -smp 2 -accel tcg,thread=multi \
  -display none -usb -nic none \
  -L "$ROOT/usr/share/qemu" -L "$ROOT/usr/share/seabios" -L "$ROOT/usr/share/vgabios" \
  -cdrom "$BASE/bnasec-2.1.1-amd64.iso" \
  -qmp unix:$SOCK,server,nowait & \
QPID=$!
for i in $(seq 1 100); do [ -S "$SOCK" ] && break; sleep 0.2; done
$PY -u "$SESS" "$SOCK" > "$BASE/drv-grub.log" 2>&1 \
  wait:9 shot:z00-grub-menu quit
wait $QPID 2>/dev/null
echo "grub done"

echo "=== 2) Firefox window via alt-tab (direct demo boot) ==="
rm -f "$SOCK"
nohup python3 -u /home/z/my-project/scripts/bnasec-beacon.py 8050 > "$BASE/beacon-F.log" 2>&1 &
qemu-system-x86_64 -m 2048 -smp 2 -accel tcg,thread=multi \
  -display none -usb -netdev user,id=n0 -device virtio-net-pci,netdev=n0,romfile= \
  -L "$ROOT/usr/share/qemu" -L "$ROOT/usr/share/seabios" -L "$ROOT/usr/share/vgabios" \
  -cdrom "$BASE/bnasec-2.1.1-amd64.iso" \
  -kernel "$BASE/isostage/vmlinuz" \
  -initrd "$BASE/isostage/initrd.img" \
  -append "boot=live persistence username=bna hostname=bnasec quiet splash bnasec-demo=1 console=ttyS0,115200 console=tty0" \
  -serial file:"$BASE/serial-sess-final.log" \
  -qmp unix:$SOCK,server,nowait & \
QPID=$!
for i in $(seq 1 100); do [ -S "$SOCK" ] && break; sleep 0.2; done

$PY -u "$SESS" "$SOCK" > "$BASE/drv-ff.log" 2>&1 \
  waitpat:'GNOME Display Manager':300 \
  waitchg:120:- \
  waitchg:150:- \
  wait:25 \
  keys:ret \
  wait:6 \
  keys:ret \
  wait:12 \

  keys:alt,tab \
  wait:8 \
  shot:z01-firefox \
  keys:alt,tab \
  wait:8 \
  shot:z02-next-window \
  keys:alt,tab \
  wait:8 \
  shot:z03-next-window \
  keys:alt,tab \
  wait:8 \
  shot:z04-next-window \
  quit
wait $QPID 2>/dev/null
echo "--- final captures end ---"
cat "$BASE/drv-ff.log"
