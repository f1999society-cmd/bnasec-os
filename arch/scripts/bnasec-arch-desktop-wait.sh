#!/bin/bash
# BNAsec-Arch: boot → login → wait for real desktop (waybar detection) → shots.
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/test-run; mkdir -p $W; rm -f $W/serial.log $W/wait-*.ppm

cat > $W/mon.py <<'EOF'
import socket, sys, time
def hmp(cmd, sock="/home/z/my-project/arch-build/test-run/qmon.sock", wait=0.3):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock); time.sleep(0.15); s.recv(4096)
    s.sendall((cmd + "\n").encode()); time.sleep(wait)
    try: r = s.recv(65536).decode(errors="replace")
    except Exception: r = ""
    s.close(); return r
hmp(sys.argv[1], wait=float(sys.argv[2]) if len(sys.argv) > 2 else 0.3)
EOF

$QEMU -L $TOOLS/qemu-root/usr/share/qemu -L $TOOLS/qemu-root/usr/share/seabios -L $TOOLS/qemu-root/usr/share/vgabios \
  -machine pc -cpu max -m 2048 -smp 4 -display none -vga std \
  -cdrom $ISO -boot d -serial file:$W/serial.log \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot &
QPID=$!
echo "qemu pid $QPID"

python3 <<'PYEOF'
import socket, time, subprocess
W = "/home/z/my-project/arch-build/test-run"

def key(k, d=0.18):
    subprocess.run(["python3", f"{W}/mon.py", f"sendkey {k}"], capture_output=True)
    time.sleep(d)

# wait for serial login prompt
t0 = time.time()
while time.time() - t0 < 300:
    try:
        if "bnasec login:" in open(f"{W}/serial.log", errors="replace").read(): break
    except Exception: pass
    time.sleep(3)
print(f"login prompt at {time.time()-t0:.0f}s")
time.sleep(8)
for ch in "bna": key(ch)
key("ret"); time.sleep(2.5)
for ch in "bnasec": key(ch)
time.sleep(1); key("ret")
print("logged in; waiting for desktop...")

# poll screendumps for waybar (bright top strip)
from PIL import Image
t0 = time.time()
found = False
while time.time() - t0 < 420:
    subprocess.run(["python3", f"{W}/mon.py", f"screendump {W}/wait-t{int(time.time()-t0)}.ppm"], capture_output=True)
    time.sleep(2)
    import glob
    f = sorted(glob.glob(f"{W}/wait-t*.ppm"))[-1]
    try:
        im = Image.open(f).convert("L")
        strip = im.crop((0, 0, im.width, 46))
        h = strip.histogram()
        lit = sum(h[60:]) / (strip.width * strip.height)
        print(f"  t={time.time()-t0:.0f}s top-strip lit={lit:.1%}")
        if lit > 0.15:
            found = True
            Image.open(f).save(f"{W}/desktop.png")
            print(f"DESKTOP DETECTED at {time.time()-t0:.0f}s")
            break
    except Exception as e:
        print("  shot err", e)
    time.sleep(18)
if not found:
    print("desktop NOT detected in 420s — saving last frame anyway")
    import glob
    f = sorted(glob.glob(f"{W}/wait-t*.ppm"))[-1]
    Image.open(f).save(f"{W}/desktop.png")
PYEOF

kill $QPID 2>/dev/null
echo "DESKTOP WAIT DONE"
