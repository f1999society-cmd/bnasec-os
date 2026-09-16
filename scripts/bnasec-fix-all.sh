#!/bin/sh
# ============================================================================
# BNAsec 2.0.0 — one-shot fix-all for real-hardware installs
#   A) restore setuid bits + put bna into the sudo group (if missing)
#   B) zram compressed swap (fixes freezes / "Force quit or wait" on 4GB RAM)
#   C) kernel tuning for USB-root live systems (fewer write-storms)
#   D) BFQ I/O scheduler (snappier desktop on slow USB sticks)
#   E) disable GNOME animations system-wide
#
# Usage:   sudo sh bnasec-fix-all.sh
# Safe to run repeatedly (idempotent). All changes persist on your stick.
# ============================================================================
set -e

if [ "$(id -u)" != "0" ]; then
  echo "Run me with sudo:  sudo sh bnasec-fix-all.sh"
  echo "(if sudo itself is broken, do the GRUB init=/bin/sh repair first)"
  exit 1
fi

echo "== A) setuid bits + sudo group =="
chown root:root /usr/bin/sudo
chmod 4755 /usr/bin/sudo
grep -q "^sudo:.*bna" /etc/group || sed -i "s/^sudo:.*/&,bna/" /etc/group
grep -q "^sudo:" /etc/group || echo "sudo:x:27:bna" >> /etc/group
chmod 4755 /usr/bin/su /usr/bin/passwd /usr/bin/chfn /usr/bin/chsh \
              /usr/bin/gpasswd /usr/bin/newgrp /usr/bin/mount \
              /usr/bin/umount /usr/bin/fusermount3 /usr/bin/pkexec \
              /usr/bin/chage /usr/bin/expiry /usr/lib/xorg/Xorg.wrap \
              /usr/lib/polkit-1/polkit-agent-helper-1 2>/dev/null || true
chmod 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper \
           /usr/sbin/unix_chkpwd 2>/dev/null || true
chmod 2755 /usr/bin/wall 2>/dev/null || true
chown -R bna:bna /home/bna 2>/dev/null || true
echo "   ok"

echo "== B) zram compressed swap (biggest win on 4GB RAM) =="
if swapon --show --noheadings 2>/dev/null | grep -q zram; then
  echo "   zram already active, skipping"
else
cat > /etc/systemd/system/bnasec-zram.service <<'EOF'
[Unit]
Description=BNAsec zram swap
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'modprobe zram && echo zstd > /sys/block/zram0/comp_algorithm && echo 4G > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon -p 100 /dev/zram0'
ExecStop=/bin/sh -c 'swapoff /dev/zram0 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable bnasec-zram.service >/dev/null 2>&1 || true
systemctl restart bnasec-zram.service
fi

echo "== C) kernel tuning (less USB write-stall) =="
cat > /etc/sysctl.d/99-bnasec-perf.conf <<'EOF'
vm.swappiness=60
vm.vfs_cache_pressure=50
vm.dirty_background_bytes=16777216
vm.dirty_bytes=134217728
EOF
sysctl --system >/dev/null 2>&1 || true

echo "== D) BFQ I/O scheduler =="
echo bfq > /etc/modules-load.d/bfq.conf
cat > /etc/udev/rules.d/60-bnasec-iosched.rules <<'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
modprobe bfq 2>/dev/null || true
for d in /sys/block/sd*/queue/scheduler; do
  [ -e "$d" ] && echo bfq > "$d" 2>/dev/null || true
done

echo "== E) GNOME animations off (system-wide, applies next login) =="
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
printf "user-db:user\nsystem-db:local\n" > /etc/dconf/profile/user
printf "[org/gnome/desktop/interface]\nenable-animations=false\n" > /etc/dconf/db/local.d/00-bnasec-perf
dconf update 2>/dev/null || true

sync
echo
echo "=== DONE ==="
free -h
echo
echo "Swap should now show ~4.0Gi. Log out/in once (or reboot) to feel"
echo "all changes. If anything still feels slow, send me the output of:"
echo "  sudo dmesg | tail -n 30"
