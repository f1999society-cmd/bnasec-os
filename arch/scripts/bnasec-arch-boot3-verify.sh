#!/bin/bash
# Boot 3: verify BOOT2 markers survived the reboot — the persistence proof.
source /home/z/my-project/arch-build/env.sh
export LD_LIBRARY_PATH="$TOOLS/qemu-root/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
cd $AB
(python3 <<'PYEOF'
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
for i in range(30):
    try: s.connect(("127.0.0.1", 4327)); break
    except Exception: time.sleep(2)
s.settimeout(2)
buf = b""
def drain(t=2):
    global buf
    end = time.time()+t
    while time.time() < end:
        try:
            d = s.recv(65536)
            if not d: raise ConnectionResetError()
            buf += d
        except socket.timeout: pass
def wait_pat(pat, mx=180):
    t0 = time.time()
    while time.time()-t0 < mx:
        drain(2)
        if pat in buf.decode(errors="replace"): return True
    return False
wait_pat("bnasec login:", 180)
time.sleep(3)
drain(1); s.sendall(b"root\n"); time.sleep(2)
s.sendall(b"bnasec\n"); wait_pat("#", 25); time.sleep(1)
s.sendall(b"echo --- PROOF ---; ls -la /run/bnasec/persist/; cat /home/bna/persist-proof.txt 2>&1; free -h | head -3; echo --- END ---\n")
wait_pat("--- END ---", 30)
time.sleep(1.5); drain(2)
t = buf.decode(errors="replace"); i = t.find("--- PROOF ---")
print(t[i:] if i > 0 else t[-900:])
PYEOF
) & PP=$!
timeout 260 $TOOLS/qemu-root/usr/bin/qemu-system-x86_64 -L $TOOLS/qemu-root/usr/share/qemu -L $TOOLS/qemu-root/usr/share/seabios -machine pc -cpu max -m 2048 -smp 4 -display none -hda test-usb.img -kernel isostage/boot/vmlinuz-linux -initrd test-run/initramfs-test.img -append "console=ttyS0 loglevel=7 bnasec.persist=force bnasec.label=BNASECARCH" -serial tcp:127.0.0.1:4327,server,nowait -no-reboot >/dev/null 2>&1
kill $PP 2>/dev/null
wait $PP 2>/dev/null
echo "BOOT3 VERIFY DONE"
