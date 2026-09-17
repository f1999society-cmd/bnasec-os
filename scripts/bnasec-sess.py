#!/usr/bin/env python3
"""BNAsec QMP session driver: waits, screendumps, keystroke injection.

Usage: bnasec-sess.py <sock> cmd [cmd...]
Commands:
  wait:<sec>       sleep N seconds (draining async QMP events)
  shot:<name>      screendump -> /home/z/my-project/bnasec-build/shots/sess-<name>.ppm
  keys:<k[,k...]>  one send-key press of listed qcodes (ret, meta_l, ctrl_l,l, shift,a)
  type:<text>      type text char by char (lowercase, digits, space . - ; \\n = Enter)
  quit             quit QEMU
"""
import json
import os
import socket
import sys
import time

OUT = "/home/z/my-project/bnasec-build/shots"

CHARMAP = {
    " ": ["spc"],
    ".": ["dot"],
    "-": ["minus"],
    "\n": ["ret"],
}
for _c in "abcdefghijklmnopqrstuvwxyz0123456789":
    CHARMAP[_c] = [_c]


def main():
    sock_path = sys.argv[1]
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    f = s.makefile("rw", encoding="utf-8", newline="\n")

    def readline_nb(timeout=30.0):
        s.settimeout(timeout)
        line = f.readline()
        s.settimeout(None)
        return line

    def rpc(payload, timeout=60.0):
        f.write(json.dumps(payload) + "\n")
        f.flush()
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = readline_nb(timeout=max(0.5, deadline - time.time()))
            if not line:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if "return" in m or "error" in m:
                return m
        return {"timeout": True}

    # greeting + capabilities
    while True:
        line = readline_nb()
        if not line:
            sys.exit("no QMP greeting")
        m = json.loads(line)
        if "QMP" in m:
            break
    rpc({"execute": "qmp_capabilities"})

    for cmd in sys.argv[2:]:
        if cmd.startswith("wait:"):
            secs = float(cmd.split(":")[1])
            time.sleep(secs)
            s.setblocking(False)
            try:
                while f.readline():
                    pass
            except Exception:
                pass
            s.setblocking(True)
        elif cmd.startswith("shot:"):
            name = cmd.split(":", 1)[1]
            out = os.path.join(OUT, f"sess-{name}.ppm")
            r = rpc({"execute": "screendump", "arguments": {"filename": out}},
                    timeout=90)
            print(f"shot {name} -> {r}", flush=True)
        elif cmd.startswith("keys:"):
            codes = cmd.split(":", 1)[1].split(",")
            keys = [{"type": "qcode", "data": c} for c in codes]
            r = rpc({"execute": "send-key", "arguments": {"keys": keys}})
            time.sleep(0.15)
            print(f"keys {codes} -> {r}", flush=True)
        elif cmd.startswith("type:"):
            text = cmd.split(":", 1)[1]
            for ch in text:
                if ch not in CHARMAP:
                    sys.exit(f"unsupported char {ch!r}")
                keys = [{"type": "qcode", "data": c} for c in CHARMAP[ch]]
                rpc({"execute": "send-key", "arguments": {"keys": keys}})
                time.sleep(0.08)
            print(f"typed {text!r}", flush=True)
        elif cmd.startswith("waitchg:"):
            # waitchg:<max_sec>:<name|->  poll screendumps until the screen changes
            import io
            from PIL import Image
            _, secs, name = cmd.split(":")
            secs = float(secs)

            def snap():
                out = "/tmp/bna-poll.ppm"
                rpc({"execute": "screendump", "arguments": {"filename": out}}, 60)
                with Image.open(out) as im:
                    g = im.convert("L").resize((64, 40))
                return list(g.getdata())

            prev = snap()
            changed = False
            deadline = time.time() + secs
            while time.time() < deadline:
                time.sleep(4)
                cur = snap()
                diff = sum(abs(a - b) for a, b in zip(prev, cur)) / len(cur)
                prev = cur
                if diff > 6.0:
                    changed = True
                    print(f"screen changed (diff {diff:.1f})", flush=True)
                    break
            if name and name != "-":
                out = os.path.join(OUT, f"sess-{name}.ppm")
                rpc({"execute": "screendump", "arguments": {"filename": out}}, 90)
                print(f"shot {name} (changed={changed})", flush=True)
        elif cmd.startswith("waitpat:"):
            # waitpat:<pattern>:<max_sec>  poll QEMU serial log file for pattern
            _, pattern, secs = cmd.split(":", 2)
            secs = float(secs)
            logfile = os.environ.get("BNA_SERIAL_LOG", "")
            deadline = time.time() + secs
            found = False
            while time.time() < deadline:
                try:
                    with open(logfile, "rb") as fh:
                        fh.seek(max(0, os.path.getsize(logfile) - 8192))
                        tail = fh.read().decode("utf-8", "replace")
                    if pattern in tail:
                        found = True
                        break
                except OSError:
                    pass
                time.sleep(2)
            print(f"waitpat {pattern!r}: found={found}", flush=True)
        elif cmd.startswith("gdlogin:"):
            # gdlogin:<user>:<pass>:<max_total_sec>  GDM login with retry + change detection
            from PIL import Image
            _, user, pw, secs = cmd.split(":", 3)
            secs = float(secs)
            deadline = time.time() + secs

            def snap():
                out = "/tmp/bna-poll.ppm"
                rpc({"execute": "screendump", "arguments": {"filename": out}}, 60)
                with Image.open(out) as im:
                    g = im.convert("L").resize((64, 40))
                return list(g.getdata())

            ok = False
            while time.time() < deadline and not ok:
                ref = snap()  # greeter reference for bounce-back detection
                rpc({"execute": "send-key",
                     "arguments": {"keys": [{"type": "qcode", "data": "esc"}]}})
                time.sleep(3)
                for ch in user:
                    rpc({"execute": "send-key",
                         "arguments": {"keys": [{"type": "qcode", "data": ch}]}})
                    time.sleep(0.1)
                rpc({"execute": "send-key",
                     "arguments": {"keys": [{"type": "qcode", "data": "ret"}]}})
                time.sleep(8)
                for ch in pw:
                    rpc({"execute": "send-key",
                         "arguments": {"keys": [{"type": "qcode", "data": ch}]}})
                    time.sleep(0.1)
                rpc({"execute": "send-key",
                     "arguments": {"keys": [{"type": "qcode", "data": "ret"}]}})
                print("login submitted", flush=True)
                base = snap()
                t_end = time.time() + 75
                while time.time() < t_end:
                    time.sleep(4)
                    cur = snap()
                    diff = sum(abs(a - b) for a, b in zip(base, cur)) / len(cur)
                    if diff > 6.0:
                        print(f"transition detected (diff {diff:.1f}); verifying",
                              flush=True)
                        time.sleep(20)
                        cur2 = snap()
                        back = sum(abs(a - b) for a, b in zip(ref, cur2)) / len(cur2)
                        if back < 4.0:
                            print("bounced back to greeter — retrying", flush=True)
                            break
                        ok = True
                        print("session confirmed", flush=True)
                        break
                if not ok:
                    print("attempt produced no session — retrying", flush=True)
            if not ok:
                sys.exit("GDM login failed after retries")
        elif cmd == "quit":
            rpc({"execute": "quit"}, timeout=30)
            break
        else:
            sys.exit(f"unknown command {cmd!r} (unquoted space in type: ?)")
    s.close()


if __name__ == "__main__":
    main()
