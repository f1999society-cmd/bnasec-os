#!/bin/bash
# BNAsec-Arch: QEMU BIOS boot test — GRUB → init → overlay → greetd → login →
# Hyprland desktop → apps, with screendump proof. Runs synchronously.
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$TOOLS/qemu-root/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/test-run
mkdir -p $W
rm -f $W/*.ppm $W/*.png $W/serial.log
[ -f $ISO ] || { echo "ISO missing — run bnasec-arch-iso.sh first"; exit 1; }
ls -la $ISO

# ---- HMP monitor helper ----
cat > $W/mon.py <<'EOF'
import socket, sys, time
def hmp(cmd, sock="/home/z/my-project/arch-build/test-run/qmon.sock", wait=0.35):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock)
    time.sleep(0.2); s.recv(4096)
    s.sendall((cmd + "\n").encode()); time.sleep(wait)
    try: r = s.recv(65536).decode(errors="replace")
    except Exception: r = ""
    s.close(); return r
if __name__ == "__main__":
    print(hmp(sys.argv[1], wait=float(sys.argv[2]) if len(sys.argv) > 2 else 0.35))
EOF

# ---- launch ----
$QEMU -L $TOOLS/qemu-root/usr/share/qemu -L $TOOLS/qemu-root/usr/share/seabios -L $TOOLS/qemu-root/usr/share/vgabios -L $TOOLS/qemu-root/usr/share/ipxe-qemu -machine pc -cpu max -m 2048 -smp 4 \
  -display none -vga std \
  -cdrom $ISO -boot d \
  -serial file:$W/serial.log \
  -monitor unix:$W/qmon.sock,server,nowait \
  -no-reboot &
QPID=$!
echo "qemu pid $QPID"
sleep 2

shot() { python3 $W/mon.py "screendump $W/$1.ppm" >/dev/null; sleep 1; }
keys() { for k in $(cat); do python3 $W/mon.py "sendkey $k" >/dev/null; sleep 0.12; done; }

wait_marker() { # wait_marker <grep-pattern> <max-seconds>
  local pat="$1" mx="$2" t=0
  while [ $t -lt $mx ]; do
    if grep -q "$pat" $W/serial.log 2>/dev/null; then echo "  marker '$pat' at ${t}s"; return 0; fi
    sleep 5; t=$((t+5))
  done
  echo "  TIMEOUT waiting for '$pat' (${mx}s)"; return 1
}

echo "=== capture GRUB menu ==="
sleep 6; shot grub

echo "=== wait for kernel/init ==="
wait_marker "bnasec-init" 300 || true
wait_marker "overlay active\|switch_root" 120 || true
wait_marker "bnasec login:" 300 || true
sleep 25
shot greetd
echo "--- serial tail:"
tail -6 $W/serial.log

echo "=== login: bna / bnasec ==="
# username
printf 'b\nn\na\nret\n' | keys
sleep 2
# password
printf 'b\nn\na\ns\ne\nc\nret\n' | keys
echo "typed credentials"

echo "=== wait for Hyprland desktop ==="
sleep 100
shot desktop-a
sleep 60
shot desktop-b

echo "=== open apps ==="
python3 $W/mon.py "sendkey meta_l-ret" >/dev/null   # SUPER+Return → kitty
sleep 25; shot kitty
python3 $W/mon.py "sendkey meta_l-b" >/dev/null     # SUPER+B → firefox
sleep 40; shot firefox
python3 $W/mon.py "sendkey meta_l-d" >/dev/null     # SUPER+D → wofi
sleep 12; shot wofi

kill $QPID 2>/dev/null || true
echo "=== done; converting PPM → PNG ==="
python3 - <<'EOF'
from PIL import Image
import glob, os
os.chdir("/home/z/my-project/arch-build/test-run")
for f in sorted(glob.glob("*.ppm")):
    Image.open(f).save(f.replace(".ppm", ".png"))
    print("png:", f.replace(".ppm", ".png"))
EOF
ls -la $W/*.png
echo "BIOS TEST COMPLETE"
