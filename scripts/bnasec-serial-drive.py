#!/usr/bin/env python3
"""BNAsec serial-console session driver: log in on ttyS0, drive the GNOME session.

Usage: bnasec-serial-drive.py <serial.sock> <qmp.sock> <logfile>
Flow: poll for 'login:' -> login bna/bnasec -> wait shell -> run GUI-launch commands
      (each command echoed with a DONE marker) -> take QMP screendumps between steps.
Screendump targets are written to /home/z/my-project/bnasec-build/shots/sess-<name>.ppm
"""
import json
import os
import socket
import sys
import time

BASE = "/home/z/my-project/bnasec-build"
OUT = os.path.join(BASE, "shots")
LOG = None


def log(msg):
    stamp = time.strftime("%H:%M:%S")
    line = f"[{stamp}] {msg}"
    print(line, flush=True)
    if LOG:
        LOG.write(line + "\n")
        LOG.flush()


def qmp_rpc(f, payload, timeout=60):
    f.write(json.dumps(payload) + "\n")
    f.flush()
    deadline = time.time() + timeout
    while time.time() < deadline:
        line = f.readline()
        if not line:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if "return" in m or "error" in m:
            return m
    return {"timeout": True}


def qmp_shot(qf, name):
    out = os.path.join(OUT, f"sess-{name}.ppm")
    r = qmp_rpc(qf, {"execute": "screendump", "arguments": {"filename": out}}, 90)
    log(f"shot {name}: {r}")


def serial_read(ss, timeout):
    ss.settimeout(timeout)
    try:
        data = ss.recv(65536)
        return data.decode("utf-8", "replace")
    except socket.timeout:
        return ""


def wait_serial(ss, pattern, max_wait, buf):
    deadline = time.time() + max_wait
    while time.time() < deadline:
        chunk = serial_read(ss, 1.0)
        if chunk:
            buf.write(chunk)
            LOG.write(chunk)
            LOG.flush()
            if pattern in buf.getvalue()[-4000:]:
                return True
    return False


def send(ss, text):
    ss.sendall(text.encode())
    time.sleep(0.3)


def main():
    global LOG
    serial_path, qmp_path, logpath = sys.argv[1], sys.argv[2], sys.argv[3]
    LOG = open(logpath, "a", encoding="utf-8")

    q = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    q.connect(qmp_path)
    qf = q.makefile("rw", encoding="utf-8", newline="\n")
    while True:
        line = qf.readline()
        if not line:
            sys.exit("no QMP greeting")
        if "QMP" in json.loads(line):
            break
    qmp_rpc(qf, {"execute": "qmp_capabilities"})

    deadline = time.time() + 60
    ss = None
    while time.time() < deadline:
        try:
            ss = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            ss.connect(serial_path)
            break
        except (FileNotFoundError, ConnectionRefusedError):
            time.sleep(0.3)
    if ss is None:
        sys.exit("serial socket never appeared")

    import io
    buf = io.StringIO()

    # 1) wait for login prompt (max 420s of boot)
    log("waiting for serial login prompt...")
    if not wait_serial(ss, "login:", 420, buf):
        sys.exit("no login prompt within 420s")
    qmp_shot(qf, "01-gdm-login")
    log("login prompt seen — logging in")

    ok = False
    for attempt in range(3):
        send(ss, "\n")
        time.sleep(1.5)
        send(ss, "bna\n")
        got_pw = wait_serial(ss, "Password", 12, buf)
        time.sleep(1.0)
        send(ss, "bnasec\n")
        time.sleep(8)
        # arithmetic marker: getty ECHO shows the raw string; only a real shell prints 42
        send(ss, "echo SH-$((7*6))\n")
        time.sleep(3)
        if wait_serial(ss, "SH-42", 12, buf):
            ok = True
            log(f"shell confirmed on attempt {attempt+1}")
            break
        log(f"login attempt {attempt+1} failed — retrying")
    if not ok:
        sys.exit("serial login failed after 3 attempts")
    send(ss, "stty -echo 2>/dev/null; echo EOFF-$((2*3))\n")
    wait_serial(ss, "EOFF-6", 15, buf)
    time.sleep(1)

    # 2) session env + instant wallpaper apply
    send(ss, "export XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 "
             "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus\n")
    time.sleep(1)
    send(ss, "echo ENV-$((3*3))-READY\n")
    wait_serial(ss, "ENV-9-READY", 30, buf)
    W = "file:///usr/share/backgrounds/bnasec/bnasec-wave.jpg"
    send(ss, f"gsettings set org.gnome.desktop.background picture-uri '{W}' && "
             f"gsettings set org.gnome.desktop.background picture-uri-dark '{W}' && "
             f"gsettings set org.gnome.desktop.screensaver picture-uri '{W}' && echo WP-$((4*4))-OK\n")
    wait_serial(ss, "WP-16-OK", 60, buf)
    log("wallpaper applied via gsettings")
    time.sleep(10)
    qmp_shot(qf, "02-gnome-desktop")

    # 3) Firefox
    send(ss, "nohup firefox >/tmp/firefox.log 2>&1 & echo FF-LAUNCHED\n")
    wait_serial(ss, "FF-LAUNCHED", 30, buf)
    log("firefox launched; waiting for window")
    time.sleep(80)
    qmp_shot(qf, "03-firefox")

    # 4) navigate to example.com (firefox has focus after window open)
    for keys in (["ctrl", "l"],):
        qmp_rpc(qf, {"execute": "send-key",
                     "arguments": {"keys": [{"type": "qcode", "data": k} for k in keys]}})
        time.sleep(1.5)
    for ch in "example.com":
        qmp_rpc(qf, {"execute": "send-key",
                     "arguments": {"keys": [{"type": "qcode", "data": ch}]}})
        time.sleep(0.08)
    qmp_rpc(qf, {"execute": "send-key",
                 "arguments": {"keys": [{"type": "qcode", "data": "ret"}]}})
    log("navigated to example.com")
    time.sleep(20)
    qmp_shot(qf, "04-firefox-page")

    # 5) GNOME Terminal with stability proofs typed inside it
    proofs = ("free -h; echo; systemctl is-active bnasec-zram.service; echo; "
              "firefox --version; echo; nmap --version 2>&1 | head -n 2; echo; "
              "uname -r; uptime; echo BNASEC-ALL-OK; exec bash")
    send(ss, f"nohup gnome-terminal -- bash -c \"{proofs}\" >/tmp/gt.log 2>&1 & echo GT-LAUNCHED\n")
    wait_serial(ss, "GT-LAUNCHED", 30, buf)
    log("gnome-terminal launched with proofs")
    time.sleep(25)
    qmp_shot(qf, "05-terminal-proofs")

    # 6) GNOME System Monitor (over everything = multitask stability proof)
    send(ss, "nohup gnome-system-monitor >/tmp/gsm.log 2>&1 & echo GSM-LAUNCHED\n")
    wait_serial(ss, "GSM-LAUNCHED", 30, buf)
    log("system monitor launched")
    time.sleep(60)
    qmp_shot(qf, "06-system-monitor")

    # 7) second terminal focused on tools (fresh window, proofs again + zram detail)
    send(ss, "nohup gnome-terminal -- bash -c 'swapon --show; echo; free -m; echo; "
             "lsmod | grep -E \"^zram|^bfq\" ; echo BNASEC-TOOLS-OK; exec bash' "
             ">/tmp/gt2.log 2>&1 & echo GT2-LAUNCHED\n")
    wait_serial(ss, "GT2-LAUNCHED", 30, buf)
    time.sleep(25)
    qmp_shot(qf, "07-multitask")
    log("session complete")

    qmp_rpc(qf, {"execute": "quit"}, 30)
    ss.close()


if __name__ == "__main__":
    main()
