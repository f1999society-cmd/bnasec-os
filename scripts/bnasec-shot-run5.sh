#!/bin/bash
# BNAsec v2.1.1 run5: serial-console driven session (deterministic) + QMP screendumps
set -u
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
S=$BASE/shots
PY=/home/z/.venv/bin/python3
SOCK=/tmp/bna-sess.sock
SSOCK=/tmp/bna-serial.sock
. "$BASE/tools-env.sh"
rm -f "$SOCK" "$SSOCK" "$BASE/serial-sess-run5.log"

qemu-system-x86_64 -m 2048 -smp 2 -accel tcg,thread=multi \
  -display none -usb -netdev user,id=n0 -device virtio-net-pci,netdev=n0,romfile= \
  -L "$ROOT/usr/share/qemu" -L "$ROOT/usr/share/seabios" -L "$ROOT/usr/share/vgabios" \
  -cdrom "$BASE/bnasec-2.1.1-amd64.iso" \
  -chardev socket,id=ser0,path=$SSOCK,server=on,wait=off,logfile=$BASE/serial-sess-run5.log \
  -serial chardev:ser0 \
  -qmp unix:$SOCK,server,nowait & \
QPID=$!
for i in $(seq 1 100); do [ -S "$SOCK" ] && break; sleep 0.2; done

$PY /home/z/my-project/scripts/bnasec-serial-drive.py "$SSOCK" "$SOCK" "$BASE/serial-drive.log"
wait $QPID 2>/dev/null

cd $S
for f in sess-*.ppm; do
  [ -f "$f" ] || continue
  /home/z/.venv/bin/python3 -c "from PIL import Image; Image.open('$f').save('${f%.ppm}.png')"
done
echo "--- zram/boot proof from serial log:"
grep -aE "Adding.*swap|zram|Started GDM|bnasec-firstboot" $BASE/serial-sess-run5.log | head -6
echo "--- run5 end ---"
