#!/bin/sh
# ============================================================================
# BNAsec 2.0.0 — on-stick sudo/setuid repair (for sticks flashed from the
# FIRST 2026-09-15 upload, which shipped with setuid bits stripped).
#
# Fixes BOTH bugs:
#   1) setuid/setgid bits on 17 system binaries (sudo, su, passwd, ...)
#   2) user 'bna' missing from the 'sudo' group (sudo would refuse anyway)
#
# HOW TO USE (no sudo needed):
#   1. At the GRUB menu highlight "BNAsec 2.0.0 - live (full persistence)"
#   2. Press 'e', move cursor to end of the line starting with 'linux',
#      after 'splash' type:  init=/bin/sh   then press Ctrl-X to boot
#   3. At the '#' prompt you are root. Type the 6 one-liners:
#        chown root:root /usr/bin/sudo
#        chmod 4755 /usr/bin/sudo
#        sed -i "s/^sudo:.*/&,bna/" /etc/group
#        grep -q "^sudo:" /etc/group || echo "sudo:x:27:bna" >> /etc/group
#        sync
#        exec /sbin/init
#   4. On the desktop, open a terminal and run this script:
#        sudo sh fix-setuid.sh
#      (sudo now works because steps 1-3 fixed it; files that don't exist
#       on your build just print harmless errors)
#
# Everything persists: your stick has full-root persistence.
# Idempotent: safe to run any number of times.
# ============================================================================
set -e
S=""
[ "$(id -u)" != "0" ] && S="sudo"

# --- fix 1: sudo binary itself (owner + setuid) ---
$S chown root:root /usr/bin/sudo
$S chmod 4755 /usr/bin/sudo

# --- fix 2: put bna into the sudo group (idempotent) ---
if $S grep -q "^sudo:.*bna" /etc/group 2>/dev/null; then
  echo "  sudo group: bna already member"
else
  $S grep -q "^sudo:" /etc/group 2>/dev/null && \
    $S sed -i "s/^sudo:.*/&,bna/" /etc/group || \
    $S sh -c 'echo "sudo:x:27:bna" >> /etc/group'
  echo "  sudo group: added bna"
fi

# --- restore the full standard setuid/setgid list ---
$S chmod 4755 /usr/bin/su /usr/bin/passwd /usr/bin/chfn /usr/bin/chsh \
              /usr/bin/gpasswd /usr/bin/newgrp /usr/bin/mount \
              /usr/bin/umount /usr/bin/fusermount3 /usr/bin/pkexec \
              /usr/bin/chage /usr/bin/expiry /usr/lib/xorg/Xorg.wrap \
              /usr/lib/polkit-1/polkit-agent-helper-1 2>/dev/null || true
$S chmod 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper \
              /usr/sbin/unix_chkpwd 2>/dev/null || true
$S chmod 2755 /usr/bin/wall 2>/dev/null || true

# --- make sure the user's home is owned by bna ---
$S chown -R bna:bna /home/bna 2>/dev/null || true

sync
echo "BNAsec setuid repair complete."
echo "Verify with:  sudo -v   (asks for bna password, must succeed)"
