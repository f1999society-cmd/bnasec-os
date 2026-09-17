#!/bin/bash
# BNAsec v2.1.1: default wallpaper fix (dconf pointed at old v2.0.0 PNG, not user's 2.jpg wave)
# tree on PolarFS (/tmp/my-project) -> suid -> patch 00-bnasec -> dconf update -> repack squashfs
set -e
BASE=/home/z/my-project/bnasec-build
R=/tmp/my-project/rootfs211
cd /home/z/my-project

U=$BASE/tools-root/usr/bin/unsquashfs

echo "=== 1) extract tree from current squashfs (to PolarFS) ==="
if [ -d $R ] && [ -f $R/usr/bin/sudo ]; then
  echo "tree already extracted — resuming"
else
  rm -rf $R
  $U -q -d $R $BASE/live/filesystem.squashfs 2>&1 | tail -1
  echo "tree: $(find $R -type f | wc -l) files, $(du -sh $R | cut -f1)"
fi
ln -sfn $R $BASE/rootfs    # chroot-env.sh + later steps expect $BASE/rootfs
df -h / | tail -1

echo "=== 2) drop old squashfs (frees 1.78G for the new one) ==="
rm -f $BASE/live/filesystem.squashfs
df -h / | tail -1

echo "=== 3) re-apply 17 setuid/setgid bits (unsquash-as-z drops them) ==="
for f in sudo su mount umount pkexec passwd chsh chfn gpasswd chage expiry fusermount3; do
  chmod 4755 $R/usr/bin/$f
done
chmod 4755 $R/usr/lib/xorg/Xorg.wrap
chmod 4755 $R/usr/lib/polkit-1/polkit-agent-helper-1
chmod 4754 $R/usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod 4754 $R/usr/sbin/unix_chkpwd
chmod 2755 $R/usr/bin/wall
N=$(find $R -xdev -perm /6000 -type f | wc -l)
echo "setuid/setgid files in tree: $N (expect 17)"
[ "$N" -eq 17 ] || { echo "FATAL: suid count $N"; exit 1; }

echo "=== 4) fix default wallpaper -> user 2.jpg (bnasec-wave) ==="
sed -i 's#file:///usr/share/backgrounds/bnasec-wallpaper.png#file:///usr/share/backgrounds/bnasec/bnasec-wave.jpg#g' \
  $R/etc/dconf/db/local.d/00-bnasec
grep -n "picture-uri" $R/etc/dconf/db/local.d/00-bnasec

echo "=== 4b) ensure no stale USER-level dconf db overrides system default ==="
if [ -f $R/home/bna/.config/dconf/user ]; then
  echo "found user dconf db:"; strings $R/home/bna/.config/dconf/user | grep -i picture || true
  rm -f $R/home/bna/.config/dconf/user
  echo "removed (system db local.d is the single source of defaults)"
fi

echo "=== 5) recompile dconf system db ==="
. repo/scripts/bnasec-chroot-env.sh
bnasec_run 'dconf update && echo DCONF-UPDATE-OK'
echo "--- compiled db now references:"; strings $R/etc/dconf/db/local | grep -F "file://" | sort -u
if strings $R/etc/dconf/db/local | grep -qF "bnasec-wallpaper.png"; then
  echo "FATAL: old wallpaper still in compiled db"; exit 1
fi
strings $R/etc/dconf/db/local | grep -qF "bnasec/bnasec-wave.jpg" || { echo "FATAL: wave not in db"; exit 1; }

echo "=== 6) mksquashfs (zstd -6, 1M blocks, proven flags) ==="
. "$BASE/tools-env.sh"
mkdir -p $BASE/live
mksquashfs $R $BASE/live/filesystem.squashfs \
  -comp zstd -Xcompression-level 6 -b 1M -all-root -noappend \
  -e boot -wildcards -e 'var/cache/apt/*' 'var/lib/apt/lists/*' 2>&1 | tail -3
ls -la $BASE/live/

echo "=== 7) verify squashfs ==="
S=$BASE/live/filesystem.squashfs
CNT=$($U -lls $S 2>/dev/null | awk 'substr($1,4,1) ~ /[sS]/ || substr($1,7,1) ~ /[sS]/' | wc -l)
echo "suid/sgid count: $CNT (expect 17)"
[ "$CNT" -eq 17 ] || { echo "FATAL: suid count"; exit 1; }
for f in usr/bin/sudo usr/lib/firefox-esr/firefox-esr \
         usr/share/backgrounds/bnasec/bnasec-wave.jpg \
         usr/share/backgrounds/bnasec/bnasec-red-moon.jpg \
         usr/share/plymouth/themes/bnasec/bnasec.plymouth \
         usr/share/plymouth/themes/bnasec/bnasec-logo.png \
         usr/lib/x86_64-linux-gnu/plymouth/two-step.so \
         etc/systemd/system/bnasec-zram.service \
         etc/systemd/system/multi-user.target.wants/bnasec-firstboot.service \
         usr/local/sbin/bnasec-firstboot \
         etc/gdm3/daemon.conf \
         usr/share/glib-2.0/schemas/15_bnasec.gschema.override \
         usr/share/glib-2.0/schemas/gschemas.compiled \
         usr/share/gnome-background-properties/bnasec.xml \
         etc/sysctl.d/99-bnasec-perf.conf \
         etc/udev/rules.d/60-bnasec-iosched.rules \
         etc/skel/Desktop/READ-ME-FIRST.txt \
         usr/share/powerlevel10k/powerlevel10k.zsh-theme; do
  $U -lls $S 2>/dev/null | grep -qF -- "$f" && echo "  OK  $f" || { echo "  MISSING $f"; exit 1; }
done
echo "--- compiled db inside squashfs (wallpaper refs):"
$U -q -cat $S etc/dconf/db/local 2>/dev/null | strings | grep -F "file://" | sort -u
echo "--- autologin (must be disabled):"
$U -q -cat $S etc/gdm3/daemon.conf 2>/dev/null | grep AutomaticLogin
echo "--- picker XML (2.jpg default + 3.jpg optional):"
$U -q -cat $S usr/share/gnome-background-properties/bnasec.xml 2>/dev/null | grep -E "name>|filename>"
echo "--- firefox ELF:"
$U -q -cat $S usr/lib/firefox-esr/firefox-esr 2>/dev/null | head -c 4 | od -c | head -1
echo "=== TREE VERIFIED ==="
df -h / | tail -1

echo "=== 8) drop extracted tree ==="
rm -rf $R
rm -f $BASE/rootfs
df -h / | tail -1
