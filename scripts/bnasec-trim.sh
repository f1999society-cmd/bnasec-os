#!/bin/bash
# Trim rootfs: drop firefox-esr, GNOME help, ruby docs, ibus dicts (non-en),
# stale locales/compiled locales; keep wifi/GPU firmware.
set -e
BASE=/home/z/my-project/bnasec-build
. /home/z/my-project/scripts/bnasec-chroot-env.sh

bnasec_run "apt-get remove -y --purge firefox-esr* 2>/dev/null || true"
bnasec_run "apt-get autoremove -y --purge 2>/dev/null || true"

bnasec_run "rm -rf /usr/share/help/* /usr/share/ri/* /usr/share/doc/*"
bnasec_run "find /usr/share/ibus/dicts -type f ! -name 'en*' -delete 2>/dev/null || rm -rf /usr/share/ibus/dicts"
bnasec_run "find /usr/share/locale -maxdepth 1 -mindepth 1 ! -name 'en*' ! -name 'locale.alias' -exec rm -rf {} + 2>/dev/null || true"

# purge compiled locales, keep only en_US.UTF-8
bnasec_run "printf 'en_US.UTF-8 UTF-8\n' > /etc/locale.gen && locale-gen --purge 2>&1 | tail -2 && update-locale LANG=en_US.UTF-8"

echo "--- trimmed sizes ---"
bnasec_run "du -s -m /usr/lib /usr/share 2>/dev/null"
bnasec_run "dpkg -l 2>/dev/null | grep -cE '^ii'"
echo "--- df host ---"
df -h / | tail -1
