#!/bin/bash
# BNAsec-Arch v1.0.1 QEMU BIOS test — no serial on normal entry: timed waits
# + screendump polling. Verifies: GRUB -> greetd -> bna/bnasec -> Hyprland
# desktop -> Super+Enter opens foot -> Super+B firefox. Runs synchronously.
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$TOOLS/qemu-root/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.1-amd64.iso
W=$AB/test-run
mkdir -p $W
rm -f $W/*.ppm $W/*.png $W/serial.log
[ -f $ISO ] || { echo "ISO missing — run bnasec-arch-iso.sh first"; exit 1; }
ls -la $ISO

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
keys() { for k in $(cat); do python3 $W/mon.py "sendkey $k" >/dev/null; sleep 0.2; done; }

echo "=== boot polling (TCG, expect greetd ~3-4 min) ==="
sleep 40; shot t040
sleep 40; shot t080
sleep 40; shot t120
sleep 40; shot t160
sleep 40; shot t200
sleep 30; shot greetd

echo "=== login: bna / bnasec ==="
printf 'b\nn\na\nret\n' | keys
sleep 3
printf 'b\nn\na\ns\ne\nc\nret\n' | keys
echo "typed credentials"
sleep 60; shot desktop-a
sleep 40; shot desktop-b

echo "=== SUPER+Enter -> foot terminal ==="
python3 $W/mon.py "sendkey meta_l-ret" >/dev/null
sleep 20; shot foot
echo "=== SUPER+B -> firefox ==="
python3 $W/mon.py "sendkey meta_l-b" >/dev/null
sleep 50; shot firefox

kill $QPID 2>/dev/null || true
echo "=== converting PPM -> PNG ==="
python3 - <<'EOF'
from PIL import Image
import glob, os
os.chdir("/home/z/my-project/arch-build/test-run")
for f in sorted(glob.glob("*.ppm")):
    Image.open(f).save(f.replace(".ppm", ".png"))
    print("png:", f.replace(".ppm", ".png"))
EOF
ls -la $W/*.png
echo "V1.0.1 BIOS TEST COMPLETE"
