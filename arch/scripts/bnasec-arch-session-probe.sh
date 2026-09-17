#!/bin/bash
# BNAsec-Arch: session state probe — login, then serial-root inspects Hyprland.
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/test-run; mkdir -p $W; rm -f $W/serial.log

$QEMU -L $TOOLS/qemu-root/usr/share/qemu -L $TOOLS/qemu-root/usr/share/seabios -L $TOOLS/qemu-root/usr/share/vgabios \
  -machine pc -cpu max -m 2048 -smp 4 -display none -vga std \
  -cdrom $ISO -boot d \
  -serial tcp:127.0.0.1:4323,server,nowait \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot &
QPID=$!
echo "qemu pid $QPID"

python3 <<'PYEOF'
import socket, time, subprocess, sys
W = "/home/z/my-project/arch-build/test-run"

def key(k, d=0.18):
    subprocess.run(["python3", f"{W}/mon.py", f"sendkey {k}"], capture_output=True)
    time.sleep(d)

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
for i in range(40):
    try: s.connect(("127.0.0.1", 4323)); break
    except Exception: time.sleep(2)
s.settimeout(2)
buf = b""
def drain(t=1.5):
    global buf
    end = time.time() + t
    while time.time() < end:
        try: buf += s.recv(65536)
        except socket.timeout: pass
def wait_pat(pat, mx=300):
    global buf
    t0 = time.time()
    while time.time() - t0 < mx:
        drain(2)
        if pat in buf.decode(errors="replace"): return True
    return False

print("waiting for login prompt...")
def tee():
    global buf
    open(f"{W}/serial-tcp.log", "a", errors="replace").write(buf.decode(errors="replace"))
ok = wait_pat("bnasec login:", 300)
tee()
if not ok:
    print("NO LOGIN PROMPT — boot failed; aborting"); sys.exit(1)
time.sleep(8)
for ch in "bna": key(ch)
key("ret"); time.sleep(2.5)
for ch in "bnasec": key(ch)
time.sleep(1); key("ret")
print("logged in; waiting 60s for session to settle...")
time.sleep(60)

# serial root: inspect session
drain(2)
s.sendall(b"\n"); time.sleep(1)
s.sendall(b"root\n"); time.sleep(1.5)
s.sendall(b"bnasec\n"); wait_pat("#", 20); time.sleep(1)
for c in ["pidof Hyprland waybar swww dunst",
          "loginctl list-sessions --no-legend",
          "ls /run/user/1000/hypr/ 2>&1 | head -3",
          "tail -20 /run/user/1000/hypr/*/hyprland.log 2>/dev/null",
          "journalctl -b --no-pager | grep -iE 'Hyprland|greetd|waybar|swww|dunst' | tail -16",
          "echo ENDMARK"]:
    s.sendall((c + "\n").encode())
    wait_pat("ENDMARK" if c == "echo ENDMARK" else "]#", 18)
    time.sleep(1.2)
drain(2)
txt = buf.decode(errors="replace")
i = txt.find("pidof")
print(txt[i:] if i > 0 else txt[-4000:])
PYEOF

kill $QPID 2>/dev/null
echo "SESSION PROBE DONE"
