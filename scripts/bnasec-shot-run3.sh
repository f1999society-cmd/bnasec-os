#!/bin/bash
# BNAsec v2.1.1 full proof session: desktop(wave) -> Firefox -> page -> terminal proofs -> system monitor
set -u
BASE=/home/z/my-project/bnasec-build
ROOT=$BASE/tools-root
S=$BASE/shots
PY=/home/z/.venv/bin/python3
SESS=/home/z/my-project/scripts/bnasec-sess.py
SOCK=/tmp/bna-sess.sock
. "$BASE/tools-env.sh"
rm -f "$SOCK" "$BASE/serial-sess-run3.log"

Q() {
  qemu-system-x86_64 -m 2048 -smp 2 -accel tcg,thread=multi \
    -display none -usb -netdev user,id=n0 -device virtio-net-pci,netdev=n0,romfile= \
    -L "$ROOT/usr/share/qemu" -L "$ROOT/usr/share/seabios" -L "$ROOT/usr/share/vgabios" \
    -cdrom "$BASE/bnasec-2.1.1-amd64.iso" \
    -serial file:"$BASE/serial-sess-run3.log" \
    -qmp unix:$SOCK,server,nowait
}

Q & QPID=$!
for i in $(seq 1 100); do [ -S "$SOCK" ] && break; sleep 0.2; done

$PY "$SESS" "$SOCK" \
  wait:225 \
  wait:30 \
  type:bna keys:ret \
  wait:3 \
  type:bnasec keys:ret \
  wait:100 \
  shot:02-gnome-desktop \
  keys:meta_l wait:12 \
  type:firefox keys:ret \
  wait:80 \
  shot:03-firefox \
  keys:ctrl,l wait:2 \
  type:example.com keys:ret \
  wait:18 \
  shot:04-firefox-page \
  keys:ctrl,alt,t wait:15 \
  shot:05-terminal \
  type:'free -h' keys:ret wait:2 \
  type:'systemctl is-active bnasec-zram' keys:ret wait:2 \
  type:'firefox --version' keys:ret wait:2 \
  type:'nmap --version' keys:ret wait:2 \
  type:uptime keys:ret \
  wait:10 \
  shot:06-terminal-proofs \
  keys:meta_l wait:12 \
  type:'system monitor' keys:ret \
  wait:55 \
  shot:07-system-monitor \
  quit
wait $QPID 2>/dev/null
echo "--- session run3 end ---"
