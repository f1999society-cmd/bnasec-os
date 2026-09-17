#!/bin/bash
# BNAsec-Arch: interactive debug probe — boots to the init debug shell (tty1)
# and types diagnostic commands via sendkey, screendumping the results.
set -e
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
QEMU=$TOOLS/qemu-root/usr/bin/qemu-system-x86_64
ISO=$AB/bnasec-arch-1.0.0-amd64.iso
W=$AB/test-run; mkdir -p $W; rm -f $W/*.ppm $W/dbg*.png

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
rm -f $W/serial.log.new

# key names per char for sendkey
send_text() { # send_text <text>
  python3 - "$@" <<'PYEOF'
import subprocess, sys, time
MAP = {' ': 'spc', '-': 'minus', '.': 'dot', '/': 'slash', '_': 'shift-minus', '=': 'equal', ';': 'semicolon', ':': 'shift-semicolon'}
text = sys.argv[1]
for ch in text:
    if ch == '\n':
        subprocess.run(["python3", "/home/z/my-project/arch-build/test-run/mon.py", "sendkey ret"], capture_output=True)
    else:
        key = MAP.get(ch, ch)
        subprocess.run(["python3", "/home/z/my-project/arch-build/test-run/mon.py", f"sendkey {key}"], capture_output=True)
    time.sleep(0.09)
PYEOF
}

# wait for FATAL marker (fresh log only)
t=0
while [ $t -lt 300 ]; do
  if [ -s $W/serial.log ] && grep -q "FATAL" $W/serial.log 2>/dev/null; then echo "FATAL at ${t}s"; break; fi
  sleep 5; t=$((t+5))
done
[ $t -ge 300 ] && { echo "no FATAL in 300s — killing"; kill $QPID; exit 1; }
sleep 6

send_text 'insmod /lib/modules/7.2.6-arch2-1/kernel/drivers/scsi/sr_mod.ko.zst
'
sleep 3
send_text 'echo RC=$?
'
sleep 2
send_text 'dmesg | tail -n 4
'
sleep 3
python3 $W/mon.py "screendump $W/dbg-insmod.ppm"
send_text 'ls /usr/lib/ | head -6
'
sleep 2
send_text 'uname -r; ls /lib/modules/
'
sleep 2
python3 $W/mon.py "screendump $W/dbg-ls.ppm"

kill $QPID 2>/dev/null
python3 - <<'EOF'
from PIL import Image
for f in ["dbg-insmod", "dbg-ls"]:
    Image.open(f"/home/z/my-project/arch-build/test-run/{f}.ppm").save(
        f"/home/z/my-project/arch-build/test-run/{f}.png")
    print("png:", f)
EOF
echo "DEBUG PROBE DONE"
