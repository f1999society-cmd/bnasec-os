#!/bin/bash
# BNAsec-Arch: attempt greeter login via VGA keys, then serial-root to read
# the auth failure from the journal — one boot, full visibility.
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
  -machine pc -cpu max -m 2048 -smp 4 -display none -vga std \
  -cdrom $ISO -boot d \
  -serial tcp:127.0.0.1:4322,server,nowait \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot &
QPID=$!
echo "qemu pid $QPID"

# --- wait for serial login prompt, then type bna/bnasec on the VGA greeter ---
python3 <<'PYEOF'
import socket, time, subprocess

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
for i in range(40):
    try: s.connect(("127.0.0.1", 4322)); break
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
wait_pat("bnasec login:", 300)
time.sleep(8)   # let greetd/tuigreet settle on tty1

def key(k):
    subprocess.run(["python3", "/home/z/my-project/arch-build/test-run/mon.py", f"sendkey {k}"], capture_output=True)
    time.sleep(0.2)
def text(t):
    for ch in t:
        key(ch)
# attempt 1
for ch in "bna": key(ch)
key("ret"); time.sleep(2.5)
for ch in "bnasec": key(ch)
time.sleep(1); key("ret")
print("credentials typed; waiting for failure + journal...")
time.sleep(25)
drain(2)
PYEOF

# --- serial root: dump auth journal + shadow state ---
python3 <<'PYEOF'
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(("127.0.0.1", 4322)); s.settimeout(2)
buf = b""
def drain(t=1.5):
    global buf
    end = time.time() + t
    while time.time() < end:
        try: buf += s.recv(65536)
        except socket.timeout: pass
def wait_pat(pat, mx=60):
    global buf
    t0 = time.time()
    while time.time() - t0 < mx:
        drain(1)
        if pat in buf.decode(errors="replace"): return True
    return False
drain(2)
s.sendall(b"\n"); time.sleep(1)
s.sendall(b"root\n"); time.sleep(1.5)
s.sendall(b"bnasec\n"); wait_pat("#", 30); time.sleep(1)
for c in ["passwd -S bna",
          "grep '^bna:' /etc/shadow | cut -c1-50",
          "S=$(grep '^bna:' /etc/shadow | cut -d: -f2 | cut -d$ -f3); openssl passwd -6 -salt $S bnasec | cut -c1-30",
          "ls -la /etc/nologin 2>&1",
          "journalctl -b --no-pager | grep -iE 'greetd|pam_unix|pam_warn|authentication' | tail -14",
          "echo ENDMARK"]:
    s.sendall((c + "\n").encode())
    wait_pat("ENDMARK" if c == "echo ENDMARK" else "]#", 30)
    time.sleep(1.2)
drain(2)
txt = buf.decode(errors="replace")
i = txt.find("passwd -S")
print(txt[i:] if i > 0 else txt[-3500:])
PYEOF

kill $QPID 2>/dev/null
echo "COMBINED AUTH PROBE DONE"
