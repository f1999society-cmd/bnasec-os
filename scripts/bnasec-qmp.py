#!/usr/bin/env python3
"""Minimal QMP client: wait N seconds in a running QEMU, take screendump, quit.
Usage: bnasec-qmp.py <socket> <command...>
Commands: wait:<sec>:<out.png> | screendump:<out.png> | quit
"""
import json
import socket
import sys
import time


def main():
    sock_path = sys.argv[1]
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    f = s.makefile("rw", encoding="utf-8", newline="\n")

    def readmsg():
        while True:
            line = f.readline()
            if not line:
                return {}

    # hello
    while True:
        line = f.readline()
        if not line:
            sys.exit("no greeting")
        m = json.loads(line)
        if "QMP" in m:
            break
    f.write(json.dumps({"execute": "qmp_capabilities"}) + "\n")
    f.flush()
    while True:
        line = f.readline()
        if not line:
            sys.exit("negotiation failed")
        if "return" in json.loads(line):
            break

    for cmd in sys.argv[2:]:
        if cmd.startswith("wait:"):
            _, secs, out = cmd.split(":")
            deadline = time.time() + float(secs)
            while time.time() < deadline:
                time.sleep(0.5)
                s.setblocking(False)
                try:
                    f.readline()
                except Exception:
                    pass
                s.setblocking(True)
            if out:
                f.write(json.dumps({"execute": "screendump",
                                    "arguments": {"filename": out}}) + "\n")
                f.flush()
                while True:
                    line = f.readline()
                    if not line:
                        break
                    m = json.loads(line)
                    if "return" in m or "error" in m:
                        print(out, "->", m.get("return") or m.get("error"))
                        break
        elif cmd.startswith("screendump:"):
            out = cmd.split(":", 1)[1]
            f.write(json.dumps({"execute": "screendump",
                                "arguments": {"filename": out}}) + "\n")
            f.flush()
            while True:
                line = f.readline()
                if not line:
                    break
                m = json.loads(line)
                if "return" in m or "error" in m:
                    print(out, "->", m.get("return") or m.get("error"))
                    break
        elif cmd == "quit":
            f.write(json.dumps({"execute": "quit"}) + "\n")
            f.flush()
            break
    s.close()


if __name__ == "__main__":
    main()
