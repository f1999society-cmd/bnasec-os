#!/bin/bash
# BNAsec v2.1.0: stage verified initramfs -> drop old squashfs -> build new squashfs -> verify
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
KVER=6.12.107+deb13-amd64

echo "=== 1) stage NEW initramfs into isostage ==="
rm -f "$BASE/isostage/initrd.img" "$BASE/isostage/vmlinuz.old" 2>/dev/null
chmod u+w "$BASE/isostage" 2>/dev/null || true
cp "$R/boot/initrd.img-$KVER" "$BASE/isostage/initrd.img"
ls -la "$BASE/isostage/"
sha256sum "$BASE/isostage/initrd.img" | cut -c1-16

echo "=== 2) drop old squashfs (rootfs tree already extracted + customized) ==="
rm -f "$BASE/old-fs.squashfs"
df -h / | tail -1

echo "=== 3) mksquashfs (zstd -6, 1M blocks, exclude boot/) ==="
. "$BASE/tools-env.sh"
mkdir -p "$BASE/live"
rm -f "$BASE/live/filesystem.squashfs"
mksquashfs "$R" "$BASE/live/filesystem.squashfs" \
  -comp zstd -Xcompression-level 6 -b 1M -all-root -noappend \
  -e boot -wildcards -e 'var/cache/apt/*' 'var/lib/apt/lists/*' 2>&1 | tail -3
ls -la "$BASE/live/"

echo "=== 4) verify squashfs contents ==="
S="$BASE/live/filesystem.squashfs"
echo "--- suid/sgid files inside new squashfs (expect 17) ---"
unsquashfs -lls "$S" 2>/dev/null | awk 'substr($1,4,1) ~ /[sS]/ || substr($1,7,1) ~ /[sS]/ {print $1, $NF}' | head -20
CNT=$(unsquashfs -lls "$S" 2>/dev/null | awk 'substr($1,4,1) ~ /[sS]/ || substr($1,7,1) ~ /[sS]/' | wc -l)
echo "suid/sgid count: $CNT"
[ "$CNT" -eq 17 ] || { echo "FATAL: suid count $CNT"; exit 1; }

for f in usr/bin/sudo usr/lib/firefox-esr/firefox-esr \
         usr/share/backgrounds/bnasec/bnasec-wave.jpg \
         usr/share/backgrounds/bnasec/bnasec-red-moon.jpg \
         usr/share/plymouth/themes/bnasec/bnasec.plymouth \
         usr/share/plymouth/themes/bnasec/bnasec-logo.png \
         usr/share/plymouth/themes/bnasec/watermark.png \
         usr/share/plymouth/themes/bnasec/animation-0036.png \
         usr/share/plymouth/themes/bnasec/throbber-0030.png \
         usr/lib/x86_64-linux-gnu/plymouth/two-step.so \
         etc/systemd/system/bnasec-zram.service \
         etc/systemd/system/multi-user.target.wants/bnasec-zram.service \
         etc/systemd/system/multi-user.target.wants/bnasec-firstboot.service \
         usr/local/sbin/bnasec-firstboot \
         usr/local/sbin/bnasec-persist-setup \
         etc/gdm3/daemon.conf \
         usr/share/glib-2.0/schemas/15_bnasec.gschema.override \
         usr/share/glib-2.0/schemas/gschemas.compiled \
         usr/share/gnome-background-properties/bnasec.xml \
         usr/share/applications/mimeapps.list \
         etc/sysctl.d/99-bnasec-perf.conf \
         etc/udev/rules.d/60-bnasec-iosched.rules \
         etc/skel/Desktop/READ-ME-FIRST.txt \
         lib/modules/6.12.107+deb13-amd64/kernel/drivers/block/zram/zram.ko.xz \
         lib/modules/6.12.107+deb13-amd64/kernel/block/bfq.ko.xz \
         usr/share/plymouth/plymouthd.defaults \
         usr/local/bin/wpscan \
         usr/share/powerlevel10k/powerlevel10k.zsh-theme; do
  unsquashfs -lls "$S" 2>/dev/null | grep -qF -- "$f" && echo "  OK  $f" || { echo "  MISSING $f"; exit 1; }
done

echo "--- autologin must be OFF inside squashfs ---"
unsquashfs -q -cat "$S" etc/gdm3/daemon.conf 2>/dev/null | grep AutomaticLogin

echo "--- firefox binary sanity (extract + file type) ---"
unsquashfs -q -cat "$S" usr/lib/firefox-esr/firefox-esr 2>/dev/null | head -c 4 | od -c | head -1

echo "=== SQUASHFS VERIFIED ==="
df -h / | tail -1
