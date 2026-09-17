#!/bin/bash
# BNAsec v2.1.1 runA: DIRECT kernel boot with bnasec-demo=1 -> autologin -> wave desktop -> firefox
set -u
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
PY=/home/z/.venv/bin/python3
SESS=/home/z/my-project/scripts/bnasec-sess.py
SOCK=/tmp/bna-sess.sock
. "$BASE/tools-env.sh"
nohup python3 -u /home/z/my-project/scripts/bnasec-beacon.py 8047 > "$BASE/beacon-A.log" 2>&1 &
rm -f "$SOCK" "$BASE/serial-sess-runA.log"
export BNA_SERIAL_LOG="$BASE/serial-sess-runA.log"

qemu-system-x86_64 -m 2048 -smp 2 -accel tcg,thread=multi \
  -display none -usb -netdev user,id=n0 -device virtio-net-pci,netdev=n0,romfile= \
  -L "$ROOT/usr/share/qemu" -L "$ROOT/usr/share/seabios" -L "$ROOT/usr/share/vgabios" \
  -cdrom "$BASE/bnasec-2.1.1-amd64.iso" \
  -kernel "$BASE/isostage/vmlinuz" \
  -initrd "$BASE/isostage/initrd.img" \
  -append "boot=live persistence username=bna hostname=bnasec quiet splash bnasec-demo=1 console=ttyS0,115200 console=tty0" \
  -serial file:"$BASE/serial-sess-runA.log" \
  -qmp unix:$SOCK,server,nowait & \
QPID=$!
for i in $(seq 1 100); do [ -S "$SOCK" ] && break; sleep 0.2; done

$PY -u "$SESS" "$SOCK" > "$BASE/drv-runA.log" 2>&1 \
  waitpat:'GNOME Display Manager':300 \
  waitchg:120:- \
  waitchg:150:- \
  wait:25 \
  keys:ret \
  wait:6 \
  keys:ret \
  wait:12 \
  shot:a02-desktop-wave \
  wait:60 \
  shot:a03-firefox \
  wait:50 \
  shot:a04-firefox-page \
  quit
wait $QPID 2>/dev/null
echo "--- runA end ---"
cat "$BASE/drv-runA.log"
