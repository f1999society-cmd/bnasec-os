#!/bin/bash
# BNAsec-Arch: after login, test if Hyprland responds to keybinds (kitty/firefox).
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/test-run; mkdir -p $W; rm -f $W/serial.log $W/kb-*.ppm

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
  -cdrom $ISO -boot d -serial tcp:127.0.0.1:4324,server,nowait \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot &
QPID=$!
echo "qemu pid $QPID"

python3 <<'PYEOF'
import time, subprocess
W = "/home/z/my-project/arch-build/test-run"
def key(k, d=0.18):
    subprocess.run(["python3", f"{W}/mon.py", f"sendkey {k}"], capture_output=True)
    time.sleep(d)
def shot(name):
    subprocess.run(["python3", f"{W}/mon.py", f"screendump {W}/kb-{name}.ppm"], capture_output=True)
    time.sleep(1.5)

t0 = time.time()
while time.time() - t0 < 280:
    try:
        if "bnasec login:" in open(f"{W}/serial.log", errors="replace").read(): break
    except Exception: pass
    time.sleep(3)
print(f"prompt at {time.time()-t0:.0f}s")
time.sleep(25)  # wait for tuigreet to actually appear
for ch in "bna": key(ch)
key("ret"); time.sleep(2.5)
for ch in "bnasec": key(ch)
time.sleep(1); key("ret")
print("logged in; settle 45s")
time.sleep(45)
shot("settle")
key("meta_l-ret"); print("SUPER+RET sent (kitty)")
time.sleep(35); shot("kitty")
key("meta_l-b"); print("SUPER+B sent (firefox)")
time.sleep(50); shot("firefox")

# serial root: inspect session processes + logs
import socket
s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s2.connect(("127.0.0.1", 4324)); s2.settimeout(2)
    buf = b""
    def drain(t=1.5):
        global buf
        end = time.time() + t
        while time.time() < end:
            try: buf += s2.recv(65536)
            except Exception: pass
    def wait_pat(pat, mx=25):
        global buf
        t0 = time.time()
        while time.time() - t0 < mx:
            drain(1)
            if pat in buf.decode(errors="replace"): return True
        return False
    drain(1); s2.sendall(b"root\n"); time.sleep(1.5)
    s2.sendall(b"bnasec\n"); wait_pat("#", 20); time.sleep(1)
    for c in ["pidof Hyprland waybar swww dunst tuigreet",
              "tail -12 /run/user/1000/hypr/*/hyprland.log 2>/dev/null",
              "journalctl -b --no-pager | grep -iE 'waybar|swww|dunst|Hyprland' | tail -8",
              "echo ENDMARK"]:
        s2.sendall((c + "\n").encode())
        wait_pat("ENDMARK" if c == "echo ENDMARK" else "]#", 18)
        time.sleep(1)
    drain(2)
    t = buf.decode(errors="replace"); i = t.find("pidof")
    print(t[i:] if i > 0 else t[-2500:])
except Exception as e:
    print("serial inspect failed:", e)
PYEOF

kill $QPID 2>/dev/null
cd $W && python3 -c "
from PIL import Image
import glob
for f in sorted(glob.glob('kb-*.ppm')):
    Image.open(f).save(f.replace('.ppm','.png')); print(f.replace('.ppm','.png'))"
echo "KEYBIND TEST DONE"
