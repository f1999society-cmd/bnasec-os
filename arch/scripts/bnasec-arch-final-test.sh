#!/bin/bash
# BNAsec-Arch: FINAL one-call QEMU BIOS verification.
# Boot → tuigreet login (VGA keys) → Hyprland desktop → apps launched via
# hyprctl from the serial-root console → screendumps + full config-error dump.
# Evidence saved incrementally. Run: bash bnasec-arch-final-test.sh [efi]
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$TOOLS/qemu-root/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/final-run
mkdir -p $W; rm -f $W/*.ppm $W/*.png $W/serial.log $W/serial.sock
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

$QEMU -L $TOOLS/qemu-root/usr/share/qemu -L $TOOLS/qemu-root/usr/share/seabios -L $TOOLS/qemu-root/usr/share/vgabios -L $TOOLS/qemu-root/usr/share/ipxe-qemu \
  -machine pc -cpu max -m 2048 -smp 4 -display none -vga std \
  -cdrom $ISO -boot d \
  -serial tcp:127.0.0.1:4321,server,nowait \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot $EXTRA &
QPID=$!
echo "qemu pid $QPID mode=$1"

shot() { python3 $W/mon.py "screendump $W/$1.ppm" >/dev/null 2>&1; sleep 1; [ -f $W/$1.ppm ] && python3 -c "from PIL import Image; Image.open('$W/$1.ppm').save('$W/$1.png')" 2>/dev/null; }
keys() { for k in $(cat); do python3 $W/mon.py "sendkey $k" >/dev/null 2>&1; sleep 0.15; done; }

T0=$SECONDS
echo "=== grub shot ==="; sleep 8; shot grub

echo "=== boot + greeter login ==="
python3 <<'PYEOF'
import socket, time, subprocess
W = "/home/z/my-project/arch-build/final-run"
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
for i in range(30):
    try: s.connect(("127.0.0.1", 4321)); break
    except Exception: time.sleep(2)
s.settimeout(1.0)
log = open(W + "/serial.log", "ab")
buf = b""
def drain(t=1.0):
    global buf
    end = time.time() + t
    while time.time() < end:
        try:
            d = s.recv(65536)
            if d: log.write(d); log.flush(); buf += d
        except socket.timeout: pass
def wait_pat(pat, mx=300):
    global buf
    t0 = time.time()
    while time.time() - t0 < mx:
        drain(1.5)
        if pat in buf.decode(errors="replace"): return True
    print(f"  TIMEOUT waiting for {pat} ({mx}s)")
    return False
def key(k, d=0.15):
    subprocess.run(["python3", f"{W}/mon.py", f"sendkey {k}"], capture_output=True)
    time.sleep(d)
print("waiting for init...")
wait_pat("bnasec-init", 240)
print("waiting for login prompt...")
wait_pat("bnasec login:", 180)
time.sleep(6)
# --- VGA greeter: bna / bnasec ---
for ch in "bna": key(ch)
key("ret"); time.sleep(4)
for ch in "bnasec": key(ch)
time.sleep(1); key("ret")
print("greeter credentials typed")
time.sleep(20)
# retry password (in case it was dropped during the auth conversation)
for ch in "bnasec": key(ch)
time.sleep(1); key("ret")
print("password retry sent")
time.sleep(70)  # desktop settles
# --- serial root console: drive apps via hyprctl ---
print("serial root login")
drain(2); s.sendall(b"\n"); time.sleep(1)
s.sendall(b"root\n"); time.sleep(2)
s.sendall(b"bnasec\n")
wait_pat("#", 40); time.sleep(1)
CMDS = [
  "export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | head -1) XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1",
  "hyprctl version | head -2",
  "hyprctl configerrors 2>&1 | head -12",
  "journalctl -b --no-pager 2>/dev/null | grep -i 'config error' | tail -12",
  "hyprctl dispatch exec kitty",
  "hyprctl dispatch exec 'wofi --show drun'",
  "hyprctl dispatch exec firefox",
  "free -h | head -2; swapon --show; echo RAMOK",
]
for c in CMDS:
    s.sendall((c + "\n").encode()); time.sleep(2.5)
    drain(1.5)
open(W + "/hyprctl-out.log", "wb").write(buf[-14000:])
print("hyprctl commands sent")
PYEOF

echo "=== app screenshots (timed against the launches above) ==="
sleep 20; shot kitty
python3 $W/mon.py "sendkey esc" >/dev/null 2>&1 || true
python3 $W/mon.py "sendkey meta_l-d" >/dev/null 2>&1; sleep 2
python3 $W/mon.py "sendkey esc" >/dev/null 2>&1 || true
sleep 6; shot wofi
sleep 35; shot firefox
sleep 5
python3 $W/mon.py "sendkey ctrl-l" >/dev/null 2>&1
python3 $W/mon.py "sendkey meta_l-ret" >/dev/null 2>&1
sleep 18; shot terminal-final
python3 $W/mon.py "sendkey meta_l-1" >/dev/null 2>&1
sleep 3; shot desktop-clean

echo "=== serial tail ==="; tail -c 1200 $W/serial.log | tr '\r' '\n' | tail -12
python3 $W/mon.py "quit" >/dev/null 2>&1 || kill $QPID 2>/dev/null || true
ls -la $W/*.png 2>/dev/null
echo "FINAL TEST DONE ($((SECONDS-T0))s)"
