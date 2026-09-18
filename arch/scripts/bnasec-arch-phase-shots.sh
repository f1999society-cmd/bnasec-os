#!/bin/bash
# BNAsec-Arch: phased screenshot run (survives sandbox process reaper).
# phase1: boot -> serial root -> greeter bna login -> settle -> IPC ->
#         wallpaper apply+verify -> desktop shot -> MIGRATE VM to disk -> quit
# phase2: resume from disk -> kitty (paint) -> shot -> wofi -> shot -> migrate
# phase3: resume -> firefox (paint) -> shots -> final desktop
# Usage: bnasec-arch-phase-shots.sh [1|2|3]
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$TOOLS/qemu-root/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/proof-run
PH=${1:-1}
ST=$W/vmstate.bin
mkdir -p $W/shots

cat > $W/mon.py <<'EOF'
import socket, sys, time
def hmp(cmd, sock="/home/z/my-project/arch-build/proof-run/qmon.sock", wait=0.3):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(6)
        s.connect(sock); time.sleep(0.15)
        try: s.recv(4096)
        except Exception: pass
        s.sendall((cmd + "\n").encode()); time.sleep(wait)
        r = b""
        try:
            while True:
                d = s.recv(65536)
                if not d: break
                r += d
                if b"(qemu)" in r: break
        except Exception: pass
        s.close()
        return r.decode(errors="replace")
    except Exception:
        return ""
hmp(sys.argv[1], wait=float(sys.argv[2]) if len(sys.argv) > 2 else 0.3)
EOF
cat > $W/ppm-stat.py <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
px = list(im.getdata())
print(sum(px) / len(px))
EOF

if [ "$PH" = "1" ]; then
  rm -f $W/*.ppm $W/*.png $W/serial.log $W/shots/* $ST
  QCMD=(-cdrom "$ISO" -boot d)
else
  QCMD=(-cdrom "$ISO" -incoming "exec:cat $ST")
fi

$QEMU -L $TOOLS/qemu-root/usr/share/qemu -L $TOOLS/qemu-root/usr/share/seabios -L $TOOLS/qemu-root/usr/share/vgabios -L $TOOLS/qemu-root/usr/share/ipxe-qemu \
  -machine pc -cpu max -m 1536 -smp 4 -display none -vga std \
  "${QCMD[@]}" \
  -serial tcp:127.0.0.1:4321,server=on \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot &
QPID=$!
echo "qemu pid $QPID phase $PH"
trap 'kill $QPID 2>/dev/null' EXIT

if [ "$PH" != "1" ]; then
  # resumed VM restores in the state it was saved (paused) -> kick it
  sleep 90   # allow migration load of ~1.3GB to finish first
  for i in $(seq 1 30); do
    sleep 4
    if python3 $W/mon.py "info status" 2>/dev/null | grep -q "paused"; then
      python3 $W/mon.py "cont" >/dev/null 2>&1
      sleep 2
      python3 $W/mon.py "info status" 2>/dev/null | grep -q "running" && break
    fi
    python3 $W/mon.py "info status" 2>/dev/null | grep -q "running" && break
  done
fi

python3 - "$PH" <<'PYEOF'
import socket, time, subprocess, sys, os
W = "/home/z/my-project/arch-build/proof-run"
PH = sys.argv[1]
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
        if t > 0:
            s.sendall(b"\x03"); time.sleep(2)
            s.sendall(b"\n"); time.sleep(1)
        scmd(f"{BENV} grim /tmp/{name}.png && echo GRIM[:-OK-{t}:]", f"GRIM[:-OK-{t}:]", 90)
        s.sendall((f"curl -sS --max-time 40 -T /tmp/{name}.png http://10.0.2.2:8050/{name}.png && echo XFER[:-OK-{t}:]\n").encode())
        time.sleep(1)
        if wait_pat(f"XFER[:-OK-{t}:]", 60): return True
        time.sleep(4)
    return False
def wait_win(cls, marker, minutes=8):
    for i in range(minutes * 3):
        scmd(f"hyprctl clients | grep -i {cls} >/dev/null && echo {marker}", marker, 15)
        if marker in buf.decode(errors="replace")[-400:]: return True
        time.sleep(4)
    return False

if PH == "1":
    print("[P1] boot...")
    wait_pat("bnasec login:", 420, quiet=False)
    s.sendall(b"root\n"); time.sleep(2)
    s.sendall(b"bnasec\n")
    wait_pat("#", 40); time.sleep(1)
    print("[P1] greeter login bna")
    for ch in "bna": key(ch)
    key("ret"); time.sleep(4)
    for ch in "bnasec": key(ch)
    time.sleep(1); key("ret")
    up = False
    for i in range(30):
        time.sleep(5); drain(1.5)
        s.sendall(b"pidof Hyprland && echo MARK-UP\n")
        time.sleep(1.5); drain(2)
        if "MARK-UP" in buf.decode(errors="replace"):
            up = True; break
    print("    Hyprland up:", up)
    if not up: sys.exit(2)
    for i in range(45):
        s.sendall(b"ls /run/user/1000/hypr/ >/dev/null 2>&1 && echo HYPR\"T-READY\"\n")
        time.sleep(4); drain(2)
        if "HYPRT-READY" in buf.decode(errors="replace"): break
    print("    runtime ready; settle 45s")
    time.sleep(45)
    ipc = False
    for i in range(6):
        s.sendall(b"export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | head -1) XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1\n")
        time.sleep(2)
        scmd("hyprctl version | head -1", "Hyprland", 20)
        if "Hyprland" in buf.decode(errors="replace")[-500:]:
            ipc = True; break
        time.sleep(6)
    print("    IPC:", ipc)
    scmd("mkdir -p /home/bna/.cache; chown bna:bna /home/bna/.cache", "]:", 15)
    scmd("awww query 2>&1 | grep -q 'displaying: image' && echo WP[:-HAS:] || echo WP[:-NO:]", "WP[:-", 20)
    if "WP[:-NO:]" in buf.decode(errors="replace")[-300:]:
        scmd("pkill awww-daemon; sleep 1; rm -f /run/user/1000/*awww*.sock", "]:", 15)
        scmd(f"{BENV} awww-daemon --format xrgb >/tmp/awww2.log 2>&1 & echo AWWW[-ST:]", "AWWW[-ST:]", 15)
        for i in range(20):
            scmd("sleep 2; awww query >/dev/null 2>&1 && echo AWWW[-ALIVE:]", "AWWW[-ALIVE:]", 12)
            if "AWWW[-ALIVE:]" in buf.decode(errors="replace")[-300:]: break
        scmd(f"{BENV} awww img /usr/share/backgrounds/bnasec/bnasec-mocha-aurora.jpg --transition-type none && echo WP[:-SET:]", "WP[:-SET:]", 50)
    scmd("awww query 2>&1 | grep -o 'displaying: image' | head -1; echo QRY[:-END:]", "QRY[:-END:]", 20)
    print("    wallpaper settle 20s")
    time.sleep(20)
    print("[P1] desktop shot")
    grim("desktop")
    print("[P1] migrating VM state")
    subprocess.run(["python3", f"{W}/mon.py", "stop"], capture_output=True)
    time.sleep(1)
    subprocess.run(["python3", f"{W}/mon.py", f'migrate -d "exec:cat > {W}/vmstate.bin"'], capture_output=True)
    for i in range(60):
        time.sleep(2)
        r = subprocess.run(["python3", f"{W}/mon.py", "info migrate"], capture_output=True, text=True)
        if "completed" in r.stdout: break
        if "failed" in r.stdout:
            print("    MIGRATE FAILED:", r.stdout[:200]); sys.exit(4)
    print("    migration done")
    subprocess.run(["python3", f"{W}/mon.py", "quit"], capture_output=True)
    print("PHASE1 DONE")

elif PH == "2":
    print("[P2] resumed; wait for shell (flush queued commands)")
    time.sleep(8); drain(3); s.sendall(b"\n"); time.sleep(2)
    wait_pat("#", 60); time.sleep(1)
    print("[P2] desktop re-shot (flagship)")
    grim("desktop")
    print("[P2] kitty")
    scmd("hyprctl dispatch exec kitty && echo KITTY[-GO:]", "KITTY[-GO:]", 20)
    kw = wait_win("kitty", "KITTY[-MAPPED:]", 6)
    print("    kitty mapped:", kw)
    time.sleep(60)
    grim("kitty")
    time.sleep(40)
    grim("kitty2", tries=2)
    scmd("pkill kitty; true", "]:", 12); time.sleep(3)
    print("[P2] wofi")
    scmd("hyprctl dispatch exec 'wofi --show drun' && echo WOFI[-GO:]", "WOFI[-GO:]", 20)
    ww = wait_win("wofi", "WOFI[-MAPPED:]", 4)
    print("    wofi mapped:", ww)
    time.sleep(15)
    grim("wofi")
    scmd("pkill wofi; true", "]:", 12); time.sleep(2)
    print("[P2] migrating")
    subprocess.run(["python3", f"{W}/mon.py", "stop"], capture_output=True)
    time.sleep(1)
    subprocess.run(["python3", f"{W}/mon.py", f'migrate -d "exec:cat > {W}/vmstate.bin"'], capture_output=True)
    for i in range(60):
        time.sleep(2)
        r = subprocess.run(["python3", f"{W}/mon.py", "info migrate"], capture_output=True, text=True)
        if "completed" in r.stdout: break
    subprocess.run(["python3", f"{W}/mon.py", "quit"], capture_output=True)
    print("PHASE2 DONE")

elif PH == "3":
    print("[P3] resumed; wait for shell")
    time.sleep(8); drain(3); s.sendall(b"\n"); time.sleep(2)
    wait_pat("#", 60); time.sleep(1)
    print("[P3] wofi retry")
    scmd("hyprctl dispatch exec 'wofi --show drun' && echo WOFI[-GO:]", "WOFI[-GO:]", 20)
    ww = wait_win("wofi", "WOFI[-MAPPED:]", 4)
    print("    wofi mapped:", ww)
    time.sleep(15)
    grim("wofi")
    scmd("pkill wofi; true", "]:", 12); time.sleep(3)
    print("[P3] firefox")
    scmd("hyprctl dispatch exec firefox http://example.com && echo FF[-GO:]", "FF[-GO:]", 20)
    fw = wait_win("firefox", "FF[-MAPPED:]", 8)
    print("    firefox mapped:", fw)
    time.sleep(110)
    grim("firefox")
    time.sleep(55)
    grim("firefox2", tries=2)
    scmd("pkill firefox; true", "]:", 12); time.sleep(5)
    print("[P3] final desktop")
    grim("desktop-final", tries=2)
    scmd("pidof waybar >/dev/null && echo BAR[:-UP:] || echo BAR[:-DOWN:]", "BAR[:-", 15)
    scmd("awww query 2>&1 | head -1", "]", 15)
    scmd("free -h | head -2 | tail -1; swapon --show | tail -1; echo SYS[-END:]", "SYS[-END:]", 20)
    drain(2)
    open(W + "/final-state.txt", "wb").write(buf[-3500:])
    subprocess.run(["python3", f"{W}/mon.py", "quit"], capture_output=True)
    print("PHASE3 DONE")

elif PH == "4":
    print("[P4] resumed; clear jammed queue")
    time.sleep(8)
    s.sendall(b"\x03"); time.sleep(3)
    s.sendall(b"\x03"); time.sleep(3)
    s.sendall(b"\n"); time.sleep(2)
    scmd("echo SHELL[:-SYNC:]", "SHELL[:-SYNC:]", 30)
    print("[P4] wofi")
    scmd("hyprctl dispatch exec 'wofi --show drun' && echo WOFI[-GO:]", "WOFI[-GO:]", 25)
    ww = wait_win("wofi", "WOFI[-MAPPED:]", 5)
    print("    wofi mapped:", ww)
    time.sleep(15)
    grim("wofi", tries=2)
    scmd("pkill wofi; true", "]:", 12); time.sleep(3)
    print("[P4] firefox")
    scmd("hyprctl dispatch exec firefox http://example.com && echo FF[-GO:]", "FF[-GO:]", 25)
    fw = wait_win("firefox", "FF[-MAPPED:]", 9)
    print("    firefox mapped:", fw)
    time.sleep(100)
    grim("firefox", tries=2)
    time.sleep(50)
    grim("firefox2", tries=2)
    scmd("pkill firefox; true", "]:", 12); time.sleep(5)
    print("[P4] final desktop")
    grim("desktop-final", tries=2)
    subprocess.run(["python3", f"{W}/mon.py", "quit"], capture_output=True)
    print("PHASE4 DONE")
PYEOF
RC=$?
echo "phase $PH rc=$RC"
ls -la $W/shots/ 2>/dev/null
