#!/bin/bash
# BNAsec-Arch: FINAL screenshot run v5 (the deliverable set).
# Sequence: greetd shot (repaint trick) -> login bna -> settle -> IPC ->
# wallpaper APPLY (unconditional) + verify 'displaying: image' -> grim desktop ->
# kitty (sole window, long paint) -> pkill -> wofi (sole) -> pkill ->
# firefox (sole, 2min paint, double grim) -> final desktop.
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
def wait_win(cls, marker, minutes=10):
    for i in range(minutes * 3):
        scmd(f"hyprctl clients | grep -i {cls} >/dev/null && echo {marker}", marker, 15)
        if marker in buf.decode(errors="replace")[-400:]: return True
        time.sleep(5)
    return False

print("[1] waiting for boot / serial prompt...")
wait_pat("bnasec login:", 480, quiet=False)
print("[2] greetd: repaint trick (type x, shot, erase)")
gmean = -1
for attempt in range(4):
    key("x"); time.sleep(2.5)
    gmean = shot("greetd")
    print(f"    attempt {attempt}: mean={gmean}")
    key("bsp"); time.sleep(1)
    if gmean > 12: break
    time.sleep(5)

print("[3] serial root shell")
s.sendall(b"root\n"); time.sleep(2)
s.sendall(b"bnasec\n")
wait_pat("#", 40); time.sleep(1)

print("[4] VGA greeter login as bna")
for ch in "bna": key(ch)
key("ret"); time.sleep(4)
for ch in "bnasec": key(ch)
time.sleep(1); key("ret")
print("    credentials typed; polling Hyprland...")
up = False
for i in range(40):
    time.sleep(5); drain(1.5)
    s.sendall(b"pidof Hyprland && echo MARK-UP\n")
    time.sleep(1.5); drain(2)
    if "MARK-UP" in buf.decode(errors="replace"):
        up = True; break
print("    Hyprland up:", up)
if not up: sys.exit(2)

print("[5] runtime sockets + settle")
ready = False
for i in range(60):
    s.sendall(b"ls /run/user/1000/hypr/ >/dev/null 2>&1 && echo HYPR\"T-READY\"\n")
    time.sleep(4); drain(2)
    if "HYPRT-READY" in buf.decode(errors="replace"):
        ready = True; break
if not ready: sys.exit(3)
print("    runtime ready; settle 60s")
time.sleep(60)

print("[6] env + IPC probe")
ipc = False
for i in range(8):
    s.sendall(b"export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | head -1) XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1\n")
    time.sleep(2)
    scmd("hyprctl version | head -1", "Hyprland", 25)
    if "Hyprland" in buf.decode(errors="replace")[-500:]:
        ipc = True; break
    time.sleep(8)
print("    IPC responsive:", ipc)

print("[7] wallpaper: ensure applied + VERIFY image displayed")
scmd("mkdir -p /home/bna/.cache; chown bna:bna /home/bna/.cache", "]:", 15)
scmd("awww query 2>&1 | grep -q 'displaying: image' && echo WP[:-HAS-IMG:] || echo WP[:-NO-IMG:]", "WP[:-", 25)
if "WP[:-NO-IMG:]" in buf.decode(errors="replace")[-300:]:
    scmd("pkill awww-daemon; sleep 2; rm -f /run/user/1000/*awww*.sock", "]:", 20)
    scmd(f"{BENV} awww-daemon --format xrgb >/tmp/awww2.log 2>&1 & echo AWWW[-STARTED:]", "AWWW[-STARTED:]", 20)
    for i in range(30):
        scmd("sleep 2; awww query >/dev/null 2>&1 && echo AWWW[-ALIVE:]", "AWWW[-ALIVE:]", 15)
        if "AWWW[-ALIVE:]" in buf.decode(errors="replace")[-300:]: break
    scmd(f"{BENV} awww img /usr/share/backgrounds/bnasec/bnasec-mocha-aurora.jpg --transition-type none && echo WP[:-SET:]", "WP[:-SET:]", 60)
# verify regardless of path taken
scmd("awww query 2>&1 | grep -o 'displaying: image.*' | head -1; echo QRY[:-END:]", "QRY[:-END:]", 25)
print("    wallpaper settle 25s")
time.sleep(25)

print("[8] grim: clean desktop (bar + wallpaper)")
grim("desktop")

print("[9] kitty (sole window, long paint)")
scmd("hyprctl dispatch exec kitty && echo KITTY[-GO:]", "KITTY[-GO:]", 25)
kw = wait_win("kitty", "KITTY[-MAPPED:]", 8)
print("    kitty mapped:", kw)
print("    kitty paint wait 75s")
time.sleep(75)
grim("kitty")
print("    kitty second paint wait 45s")
time.sleep(45)
grim("kitty2", tries=2)
scmd("pkill kitty; true", "]:", 15); time.sleep(4)

print("[10] wofi (sole window)")
scmd("hyprctl dispatch exec 'wofi --show drun' && echo WOFI[-GO:]", "WOFI[-GO:]", 25)
ww = wait_win("wofi", "WOFI[-MAPPED:]", 5)
print("    wofi mapped:", ww)
time.sleep(15)
grim("wofi")
scmd("pkill wofi; true", "]:", 15); time.sleep(3)

print("[11] firefox (sole window, long paint)")
scmd("hyprctl dispatch exec firefox http://example.com && echo FF[-GO:]", "FF[-GO:]", 25)
fw = wait_win("firefox", "FF[-MAPPED:]", 12)
print("    firefox mapped:", fw)
print("    firefox paint wait 120s")
time.sleep(120)
grim("firefox")
print("    firefox extra 60s")
time.sleep(60)
grim("firefox2", tries=2)
scmd("pkill firefox; true", "]:", 15); time.sleep(6)

print("[12] final clean desktop")
grim("desktop-final", tries=2)
scmd("pidof waybar >/dev/null && echo BAR[:-FINAL-UP:] || echo BAR[:-FINAL-DOWN:]", "BAR[:-FINAL-", 20)
scmd("awww query 2>&1 | head -1", "]", 20)
scmd("free -h | head -2 | tail -1; swapon --show | tail -1; echo SYS[-END:]", "SYS[-END:]", 25)
drain(2)
open(W + "/final-state.txt", "wb").write(buf[-4000:])
print("PROOF SEQUENCE DONE")
PYEOF
RC=$?
ls -la $W/shots/ 2>/dev/null
echo "GRIM PROOF DONE rc=$RC"
