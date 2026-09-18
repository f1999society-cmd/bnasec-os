#!/bin/bash
# BNAsec-Arch: FINAL one-call QEMU BIOS verification — boot → login → Hyprland
# desktop → kitty/firefox/wofi shots. Evidence saved incrementally so a timeout
# never loses captured proof. Run: bash bnasec-arch-final-test.sh [efi]
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$TOOLS/qemu-root/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/final-run
mkdir -p $W; rm -f $W/*.ppm $W/*.png $W/serial.log
[ -f $ISO ] || { echo "ISO missing"; exit 1; }

cat > $W/mon.py <<'EOF'
import socket, sys, time
def hmp(cmd, sock="/home/z/my-project/arch-build/final-run/qmon.sock", wait=0.3):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock); time.sleep(0.15); s.recv(4096)
    s.sendall((cmd + "\n").encode()); time.sleep(wait)
    try: r = s.recv(65536).decode(errors="replace")
    except Exception: r = ""
    s.close(); return r
hmp(sys.argv[1], wait=float(sys.argv[2]) if len(sys.argv) > 2 else 0.3)
EOF

EXTRA=""
[ "$1" = "efi" ] && EXTRA="-bios $TOOLS/qemu-root/usr/share/OVMF/OVMF_CODE.fd"
[ "$1" = "efi" ] && ls $TOOLS/qemu-root/usr/share/OVMF/ | head -3

$QEMU -L $TOOLS/qemu-root/usr/share/qemu -L $TOOLS/qemu-root/usr/share/seabios -L $TOOLS/qemu-root/usr/share/vgabios -L $TOOLS/qemu-root/usr/share/ipxe-qemu -L $TOOLS/qemu-root/usr/share/ovmf -L $TOOLS/qemu-root/usr/share/OVMF \
  -machine pc -cpu max -m 2048 -smp 4 -display none -vga std \
  -cdrom $ISO -boot d -serial file:$W/serial.log \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot $EXTRA &
QPID=$!
echo "qemu pid $QPID mode=$1"

shot() { python3 $W/mon.py "screendump $W/$1.ppm" >/dev/null 2>&1; sleep 1; [ -f $W/$1.ppm ] && python3 -c "from PIL import Image; Image.open('$W/$1.ppm').save('$W/$1.png')" 2>/dev/null; }
keys() { for k in $(cat); do python3 $W/mon.py "sendkey $k" >/dev/null 2>&1; sleep 0.15; done; }
wait_pat() { local pat="$1" mx="$2" t=0; while [ $t -lt $mx ]; do grep -q "$pat" $W/serial.log 2>/dev/null && { echo "  [$pat] at ${t}s"; return 0; }; sleep 3; t=$((t+3)); done; echo "  TIMEOUT: $pat (${mx}s)"; return 1; }

T0=$SECONDS
echo "=== grub shot (t+8s) ==="; sleep 8; shot grub

echo "=== waiting for init/login prompt (up to 330s) ==="
wait_pat "bnasec-init" 210 || true
wait_pat "bnasec login:" 150 || { sleep 20; shot stuck; tail -4 $W/serial.log; }
sleep 6
shot greetd
echo "=== typing bna/bnasec ==="
printf 'b\nn\na\nret\n' | keys
sleep 4   # wait for tuigreet to process username (Please wait...) and show Password prompt
printf 'b\nn\na\ns\ne\nc\nret\n' | keys
shot after-login
sleep 14
# retry: if the password keystrokes were dropped during the auth conversation,
# the Password prompt is up again — retype; if login already succeeded these
# chars land on the desktop harmlessly
printf 'b\nn\na\ns\ne\nc\nret\n' | keys

echo "=== waiting for waybar desktop (up to 210s) ==="
FOUND=0
while [ $((SECONDS-T0)) -lt 460 ]; do
  shot probe
  python3 - <<'PYEOF' && { FOUND=1; break; } || true
from PIL import Image
im = Image.open("/home/z/my-project/arch-build/final-run/probe.ppm").convert("L")
strip = im.crop((0, 0, im.width, 46)); h = strip.histogram()
lit = sum(h[60:]) / (strip.width * strip.height)
import shutil
if lit > 0.15:
    shutil.copy("/home/z/my-project/arch-build/final-run/probe.png", "/home/z/my-project/arch-build/final-run/desktop.png")
    print(f"DESKTOP detected lit={lit:.0%}")
    raise SystemExit(0)
raise SystemExit(1)
PYEOF
  sleep 10
done
[ $FOUND = 1 ] && echo "=== DESKTOP OK ===" || echo "=== desktop not detected; shots saved anyway ==="

if [ $FOUND = 1 ]; then
  echo "=== apps: kitty (SUPER+Return) ==="
  python3 $W/mon.py "sendkey meta_l-ret" >/dev/null 2>&1
  sleep 22; shot kitty
  echo "=== apps: wofi (SUPER+D) ==="
  python3 $W/mon.py "sendkey meta_l-d" >/dev/null 2>&1
  sleep 8; shot wofi
  python3 $W/mon.py "sendkey esc" >/dev/null 2>&1
  echo "=== apps: firefox (SUPER+B) ==="
  python3 $W/mon.py "sendkey meta_l-b" >/dev/null 2>&1
  sleep 45; shot firefox
fi

echo "=== serial tail ==="; tail -5 $W/serial.log
python3 $W/mon.py "quit" >/dev/null 2>&1 || kill $QPID 2>/dev/null || true
ls -la $W/*.png 2>/dev/null
echo "FINAL TEST DONE ($((SECONDS-T0))s)"
