#!/bin/bash
# BNAsec-Arch: REAL-compositor proof run v3.
# Changes vs v2:
#  - apps launched via runuser (direct wayland clients, NO hyprctl dependency)
#  - wallpaper repaired live: restart awww-daemon as bna, wait-for-socket, apply, verify
#  - generous paint waits for TCG-emulated GL (kitty 40s+, firefox 90s+)
#  - pulls /tmp/wp.log + /tmp/awww2.log for diagnostics
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$TOOLS/qemu-root/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/proof-run
mkdir -p $W/shots; rm -f $W/*.ppm $W/*.png $W/serial.log $W/shots/*

cat > $W/put-server.py <<'EOF'
import http.server, os, sys
OUT = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_PUT(self):
        n = int(self.headers.get('Content-Length', 0))
        data = self.rfile.read(n)
        name = os.path.basename(self.path) or "unnamed.png"
        open(os.path.join(OUT, name), 'wb').write(data)
        self.send_response(201); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', 8050), H).serve_forever()
EOF
python3 $W/put-server.py $W/shots & SRV=$!
echo "put server pid $SRV"

cat > $W/mon.py <<'EOF'
import socket, sys, time
def hmp(cmd, sock="/home/z/my-project/arch-build/proof-run/qmon.sock", wait=0.3):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock); time.sleep(0.15); s.recv(4096)
    s.sendall((cmd + "\n").encode()); time.sleep(wait)
    try: r = s.recv(65536).decode(errors="replace")
    except Exception: r = ""
    s.close(); return r
hmp(sys.argv[1], wait=float(sys.argv[2]) if len(sys.argv) > 2 else 0.3)
EOF

cat > $W/ppm-stat.py <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
px = list(im.getdata())
print(sum(px) / len(px))
EOF

$QEMU -L $TOOLS/qemu-root/usr/share/qemu -L $TOOLS/qemu-root/usr/share/seabios -L $TOOLS/qemu-root/usr/share/vgabios -L $TOOLS/qemu-root/usr/share/ipxe-qemu \
  -machine pc -cpu max -m 2048 -smp 4 -display none -vga std \
  -cdrom $ISO -boot d \
  -serial tcp:127.0.0.1:4321,server,nowait \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot &
QPID=$!
echo "qemu pid $QPID"
trap 'kill $QPID $SRV 2>/dev/null' EXIT

key() { python3 $W/mon.py "sendkey $1" >/dev/null 2>&1; sleep 0.15; }

python3 <<'PYEOF'
import socket, time, subprocess, sys, os
W = "/home/z/my-project/arch-build/proof-run"
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
def wait_pat(pat, mx=300, quiet=True):
    global buf
    t0 = time.time()
    while time.time() - t0 < mx:
        drain(1.5)
        if pat in buf.decode(errors="replace"): return True
    if not quiet: print(f"  TIMEOUT waiting for {pat} ({mx}s)")
    return False
def key(k, d=0.18):
    subprocess.run(["python3", f"{W}/mon.py", f"sendkey {k}"], capture_output=True)
    time.sleep(d)
def scmd(c, outpat, mx=45, pre=0.7):
    s.sendall((c + "\n").encode())
    time.sleep(pre)
    ok = wait_pat(outpat, mx)
    time.sleep(0.5)
    return ok
def shot(name):
    subprocess.run(["python3", f"{W}/mon.py", f"screendump {W}/{name}.ppm"], capture_output=True)
    time.sleep(1.2)
    p = f"{W}/{name}.ppm"
    if not os.path.exists(p): return -1
    r = subprocess.run(["python3", f"{W}/ppm-stat.py", p], capture_output=True, text=True)
    try: mean = float(r.stdout.strip())
    except Exception: return -1
    subprocess.run(["python3", "-c",
      f"from PIL import Image; Image.open('{p}').save('{W}/{name}.png')"], capture_output=True)
    return mean
BENV = "runuser -u bna -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 HOME=/home/bna"
def grim(name, tries=3):
    for t in range(tries):
        scmd(f"{BENV} grim /tmp/{name}.png && echo GRIM[:-OK-{t}:]", f"GRIM[:-OK-{t}:]", 50)
        s.sendall((f"curl -sS --max-time 40 -T /tmp/{name}.png http://10.0.2.2:8050/{name}.png && echo XFER[:-OK-{t}:]\n").encode())
        time.sleep(1)
        if wait_pat(f"XFER[:-OK-{t}:]", 60): return True
        time.sleep(6)
    return False

print("[1] waiting for boot / serial prompt...")
wait_pat("bnasec login:", 480, quiet=False)

print("[2] greetd screendump (force repaint + black retry)")
gmean = -1
for attempt in range(6):
    key("shift"); time.sleep(2)
    gmean = shot("greetd")
    print(f"    attempt {attempt}: mean={gmean}")
    if gmean > 12: break
    time.sleep(6)

print("[3] serial root shell")
s.sendall(b"root\n"); time.sleep(2)
s.sendall(b"bnasec\n")
wait_pat("#", 40); time.sleep(1)

print("[4] VGA greeter login as bna")
for ch in "bna": key(ch)
key("ret"); time.sleep(4)
for ch in "bnasec": key(ch)
time.sleep(1); key("ret")
print("    credentials typed; polling Hyprland process...")
up = False
for i in range(40):
    time.sleep(5); drain(1.5)
    s.sendall(b"pidof Hyprland && echo MARK-UP\n")
    time.sleep(1.5); drain(2)
    if "MARK-UP" in buf.decode(errors="replace"):
        up = True; break
print("    Hyprland process up:", up)
if not up:
    s.sendall(b"journalctl -b --no-pager | grep -iE 'greetd|pam|hyprland' | tail -25\n")
    time.sleep(3); drain(3)
    open(W + "/auth-fail.log", "wb").write(buf[-8000:])
    sys.exit(2)

print("[5] waiting for Hyprland runtime sockets...")
ready = False
for i in range(60):
    s.sendall(b"ls /run/user/1000/hypr/ >/dev/null 2>&1 && echo HYPR\"T-READY\"\n")
    time.sleep(4); drain(2)
    if "HYPRT-READY" in buf.decode(errors="replace"):
        ready = True; break
print("    runtime ready:", ready)
if not ready: sys.exit(3)
print("    startup-burst settle (60s)...")
time.sleep(60)

print("[6] hyprctl IPC probe (retry up to 8x)")
ipc = False
for i in range(8):
    s.sendall(b"export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | head -1) XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1\n")
    time.sleep(2)
    scmd("hyprctl version | head -1", "Hyprland", 25)
    if "Hyprland" in buf.decode(errors="replace")[-500:]:
        ipc = True; break
    time.sleep(8)
print("    IPC responsive:", ipc)

print("[7] wallpaper repair")
scmd("cat /tmp/wp.log 2>/dev/null | tail -3; echo WPLOG[:-END:]", "WPLOG[:-END:]", 20)
scmd("pkill awww-daemon; sleep 2; rm -f /run/user/1000/*awww*.sock; echo AWWW[:-CLEAN:]", "AWWW[:-CLEAN:]", 25)
scmd(f"{BENV} awww-daemon --format xrgb >/tmp/awww2.log 2>&1 & echo AWWW[-STARTED:]", "AWWW[-STARTED:]", 20)
awok = False
for i in range(30):
    scmd("sleep 2; awww query >/dev/null 2>&1 && echo AWWW[-ALIVE:]", "AWWW[-ALIVE:]", 15)
    if "AWWW[-ALIVE:]" in buf.decode(errors="replace")[-300:]:
        awok = True; break
print("    awww daemon alive:", awok)
if awok:
    scmd(f"{BENV} awww img /usr/share/backgrounds/bnasec/bnasec-mocha-aurora.jpg && echo WP[:-SET:]", "WP[:-SET:]", 60)
    scmd("awww query 2>&1 | head -1; echo QRY[:-END:]", "QRY[:-END:]", 30)
scmd("tail -2 /tmp/awww2.log 2>/dev/null; echo ALOG[:-END:]", "ALOG[:-END:]", 15)
drain(2)
open(W + "/wallpaper-state.txt", "wb").write(buf[-2500:])
time.sleep(12)
print("[8] grim desktop (wallpaper + bar)")
grim("desktop")

print("[9] kitty via runuser")
scmd(f"{BENV} kitty >/tmp/kitty.log 2>&1 & echo KITTY[-GO:]", "KITTY[-GO:]", 20)
for i in range(20):
    scmd("pidof kitty >/dev/null && echo KITTY[-PID:]", "KITTY[-PID:]", 12)
    if "KITTY[-PID:]" in buf.decode(errors="replace")[-300:]: break
    time.sleep(3)
print("    kitty paint wait 40s"); time.sleep(40)
grim("kitty")

print("[10] wofi via runuser")
scmd(f"{BENV} wofi --show drun >/tmp/wofi.log 2>&1 & echo WOFI[-GO:]", "WOFI[-GO:]", 20)
time.sleep(18)
grim("wofi")
scmd("pkill wofi; true", "]:", 15)

print("[11] firefox via runuser")
scmd(f"{BENV} firefox http://example.com >/tmp/ff.log 2>&1 & echo FF[-GO:]", "FF[-GO:]", 20)
for i in range(24):
    scmd("pidof firefox >/dev/null && echo FF[-PID:]", "FF[-PID:]", 12)
    if "FF[-PID:]" in buf.decode(errors="replace")[-300:]: break
    time.sleep(4)
print("    firefox paint wait 90s"); time.sleep(90)
grim("firefox", tries=2)
print("    extra firefox settle 45s"); time.sleep(45)
grim("firefox2", tries=2)

print("[12] final clean desktop")
grim("desktop-final", tries=2)
scmd("hyprctl clients 2>&1 | head -20; echo CLI[:-END:]", "CLI[:-END:]", 25)
drain(2)
open(W + "/final-state.txt", "wb").write(buf[-3500:])
print("PROOF SEQUENCE DONE")
PYEOF
RC=$?

python3 $W/mon.py "screendump $W/desktop-qemu.ppm" >/dev/null 2>&1 || true
sleep 1
[ -f $W/desktop-qemu.ppm ] && python3 -c "from PIL import Image; Image.open('$W/desktop-qemu.ppm').save('$W/desktop-qemu.png')" 2>/dev/null
ls -la $W/shots/ 2>/dev/null
echo "GRIM PROOF DONE rc=$RC"
