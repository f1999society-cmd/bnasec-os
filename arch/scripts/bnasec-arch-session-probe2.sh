#!/bin/bash
# BNAsec-Arch: login + settle + serial-root inspection of the session state.
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/test-run; mkdir -p $W; rm -f $W/serial.log

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
  -machine pc -cpu max -m 2048 -smp 4 -display none -vga virtio \
  -cdrom $ISO -boot d \
  -serial tcp:127.0.0.1:4325,server,nowait \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot &
QPID=$!
echo "qemu pid $QPID"

python3 <<'PYEOF'
import socket, time, subprocess
W = "/home/z/my-project/arch-build/test-run"
def key(k, d=0.2):
    subprocess.run(["python3", f"{W}/mon.py", f"sendkey {k}"], capture_output=True)
    time.sleep(d)
def shot(name):
    subprocess.run(["python3", f"{W}/mon.py", f"screendump {W}/{name}.ppm"], capture_output=True)
    time.sleep(1.5)

# serial socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
for i in range(40):
    try: s.connect(("127.0.0.1", 4325)); break
    except Exception: time.sleep(2)
s.settimeout(2)
buf = b""
def drain(t=1.5):
    global buf
    end = time.time() + t
    while time.time() < end:
        try:
            d = s.recv(65536)
            if not d: raise ConnectionResetError()
            buf += d
        except socket.timeout: pass
def wait_pat(pat, mx=200):
    global buf
    t0 = time.time()
    while time.time() - t0 < mx:
        drain(2)
        if pat in buf.decode(errors="replace"): return True
    return False

t0 = time.time()
wait_pat("bnasec login:", 200)
print(f"serial prompt at {time.time()-t0:.0f}s")
time.sleep(30)  # tuigreet must be visibly up before typing
shot("pretype")
for ch in "bna": key(ch)
key("ret"); time.sleep(3)
for ch in "bnasec": key(ch)
time.sleep(1.2); key("ret")
print("typed; settle 45s")
time.sleep(45)
shot("settle")

# serial root inspection
drain(1); s.sendall(b"root\n"); time.sleep(2)
s.sendall(b"bnasec\n")
buf = b""
wait_pat("#", 25); time.sleep(1)
for c in ["pidof Hyprland waybar swww dunst tuigreet",
          "loginctl list-sessions --no-legend 2>&1",
          "tail -14 /run/user/1000/hypr/*/hyprland.log 2>/dev/null",
          "journalctl -b --no-pager | grep -iE 'Hyprland|waybar|swww|greetd' | tail -10",
          "echo ENDMARK"]:
    s.sendall((c + "\n").encode())
    wait_pat("ENDMARK" if c == "echo ENDMARK" else "]#", 20)
    time.sleep(1)
drain(2)
t = buf.decode(errors="replace"); i = t.find("pidof")
print("==== INSPECT ====")
print(t[i:i+3500] if i > 0 else t[-3000:])
PYEOF

kill $QPID 2>/dev/null
cd $W && python3 -c "
from PIL import Image
for f in ['pretype','settle']:
    try: Image.open(f+'.ppm').save(f+'.png'); print(f+'.png')
    except Exception as e: print(f, e)"
echo "SESSION PROBE DONE"
