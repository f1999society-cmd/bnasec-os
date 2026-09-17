#!/bin/bash
# BNAsec-Arch: serial-console auth debugger — root login over TCP serial,
# inspect shadow/PAM/greetd state live.
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/test-run; mkdir -p $W; rm -f $W/serial-dbg.log

$QEMU -L $TOOLS/qemu-root/usr/share/qemu -L $TOOLS/qemu-root/usr/share/seabios -L $TOOLS/qemu-root/usr/share/vgabios \
  -machine pc -cpu max -m 2048 -smp 4 -display none -vga std \
  -cdrom $ISO -boot d \
  -serial tcp:127.0.0.1:4321,server,nowait \
  -monitor unix:$W/qmon.sock,server,nowait -no-reboot &
QPID=$!
echo "qemu pid $QPID"

python3 <<'PYEOF'
import socket, time, sys

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
for i in range(30):
    try: s.connect(("127.0.0.1", 4321)); break
    except Exception: time.sleep(2)
s.settimeout(2)
buf = b""
def drain(t=1.0):
    global buf
    end = time.time() + t
    while time.time() < end:
        try: buf += s.recv(65536)
        except socket.timeout: pass
def wait_pat(pat, mx=240):
    global buf
    t0 = time.time()
    while time.time() - t0 < mx:
        drain(2)
        txt = buf.decode(errors="replace")
        if pat in txt: return True
    return False

print("waiting for login prompt...")
if not wait_pat("bnasec login:", 300):
    print("TIMEOUT waiting for login"); sys.exit(1)
time.sleep(1)
s.sendall(b"root\n"); time.sleep(1.5)
s.sendall(b"bnasec\n")
wait_pat("#", 30)
time.sleep(1)
cmds = [
    "passwd -S bna",
    "grep -E '^(root|bna):' /etc/shadow | cut -c1-30",
    "ls -la /etc/shadow",
    "grep -r . /etc/pam.d/greetd",
    "journalctl -b --no-pager | grep -iE 'greetd|pam|auth' | tail -12",
    "echo DONE-MARKER",
]
for c in cmds:
    s.sendall((c + "\n").encode())
    wait_pat("DONE-MARKER" if c.startswith("echo") else "]\#", 20)
    time.sleep(1.2)
drain(2)
txt = buf.decode(errors="replace")
# trim to the interesting part
idx = txt.find("root\n")
print(txt[idx:idx+4000] if idx > 0 else txt[-4000:])
PYEOF

kill $QPID 2>/dev/null
echo "SERIAL AUTH DEBUG DONE"
