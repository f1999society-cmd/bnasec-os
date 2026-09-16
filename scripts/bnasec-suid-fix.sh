#!/bin/bash
# BNAsec setuid repair: build override files and append into filesystem.squashfs
# Fixes: (1) all setuid/setgid bits stripped during sandbox recovery unsquash
#        (2) bna missing from sudo group
#        (3) boot-time self-repair unit as insurance
set -e
BASE=/home/z/my-project/bnasec-build
SQ=$BASE/sqfix
OV=$SQ/override
T=$BASE/tools-root
export PATH="$T/usr/bin:$T/usr/sbin:$T/bin:$PATH"
export LD_LIBRARY_PATH="$T/usr/lib/x86_64-linux-gnu:$T/lib/x86_64-linux-gnu"

echo "=== 1) extract affected files from image ==="
rm -rf $SQ/oext $OV
mkdir -p $OV
unsquashfs -n -d $SQ/oext $SQ/fs.squashfs \
  usr/bin/sudo usr/bin/su usr/bin/mount usr/bin/umount usr/bin/pkexec \
  usr/bin/passwd usr/bin/chsh usr/bin/chfn usr/bin/gpasswd usr/bin/chage \
  usr/bin/expiry usr/bin/fusermount3 usr/bin/wall \
  usr/lib/xorg/Xorg.wrap usr/lib/polkit-1/polkit-agent-helper-1 \
  usr/lib/dbus-1.0/dbus-daemon-launch-helper usr/sbin/unix_chkpwd \
  etc/group etc/gshadow usr/local/sbin/bnasec-firstboot 2>&1 | tail -1

echo "=== 2) stage override tree ==="
mkdir -p $OV/usr/bin $OV/usr/lib/xorg $OV/usr/lib/polkit-1 $OV/usr/lib/dbus-1.0 \
         $OV/usr/sbin $OV/usr/local/sbin $OV/etc/systemd/system/multi-user.target.wants

# setuid root 4755
for f in sudo su mount umount pkexec passwd chsh chfn gpasswd chage expiry fusermount3; do
  cp $SQ/oext/usr/bin/$f $OV/usr/bin/ && chmod 4755 $OV/usr/bin/$f
done
cp $SQ/oext/usr/lib/xorg/Xorg.wrap $OV/usr/lib/xorg/ && chmod 4755 $OV/usr/lib/xorg/Xorg.wrap
cp $SQ/oext/usr/lib/polkit-1/polkit-agent-helper-1 $OV/usr/lib/polkit-1/ && chmod 4755 $OV/usr/lib/polkit-1/polkit-agent-helper-1
# setgid 2755
cp $SQ/oext/usr/bin/wall $OV/usr/bin/ && chmod 2755 $OV/usr/bin/wall
# 4754 helpers
cp $SQ/oext/usr/lib/dbus-1.0/dbus-daemon-launch-helper $OV/usr/lib/dbus-1.0/ && chmod 4754 $OV/usr/lib/dbus-1.0/dbus-daemon-launch-helper
cp $SQ/oext/usr/sbin/unix_chkpwd $OV/usr/sbin/ && chmod 4754 $OV/usr/sbin/unix_chkpwd

echo "=== 3) group membership: bna -> sudo ==="
sed -i 's/^sudo:x:27:$/sudo:x:27:bna/' $SQ/oext/etc/group
grep -q '^sudo:.*bna' $SQ/oext/etc/group || sed -i 's/^sudo:x:27:/sudo:x:27:bna,/' $SQ/oext/etc/group
grep '^sudo' $SQ/oext/etc/group
sed -i 's/^sudo:\*::$/sudo:*::bna/' $SQ/oext/etc/gshadow
grep -q '^sudo:.*bna' $SQ/oext/etc/gshadow || sed -i 's/^sudo:\*:::/sudo:*::bna,/' $SQ/oext/etc/gshadow
grep '^sudo' $SQ/oext/etc/gshadow
cp $SQ/oext/etc/group $OV/etc/ && cp $SQ/oext/etc/gshadow $OV/etc/

echo "=== 4) updated firstboot (adds sudo membership at runtime too) ==="
cat > $OV/usr/local/sbin/bnasec-firstboot << 'EOF'
#!/bin/bash
# BNAsec first-boot: set live user credentials + default shell + sudo group
set -e
mkdir -p /var/lib/bnasec
if id bna >/dev/null 2>&1; then
  echo 'bna:bna' | chpasswd
  usermod -s /usr/bin/zsh bna || true
  usermod -aG sudo bna 2>/dev/null || true
fi
touch /var/lib/bnasec/firstboot-done
EOF
chmod 755 $OV/usr/local/sbin/bnasec-firstboot

echo "=== 5) boot-time suid self-repair unit (insurance) ==="
cat > $OV/usr/local/sbin/bnasec-suid-repair << 'EOF'
#!/bin/sh
# BNAsec: ensure privileged binaries keep their setuid bits (idempotent)
for f in sudo su mount umount pkexec passwd chsh chfn gpasswd chage newgrp expiry fusermount3; do
  [ -f /usr/bin/$f ] && chmod 4755 /usr/bin/$f
done
[ -f /usr/bin/wall ] && chmod 2755 /usr/bin/wall
[ -f /usr/lib/xorg/Xorg.wrap ] && chmod 4755 /usr/lib/xorg/Xorg.wrap
[ -f /usr/lib/polkit-1/polkit-agent-helper-1 ] && chmod 4755 /usr/lib/polkit-1/polkit-agent-helper-1
[ -f /usr/lib/dbus-1.0/dbus-daemon-launch-helper ] && chmod 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper
[ -f /usr/sbin/unix_chkpwd ] && chmod 4754 /usr/sbin/unix_chkpwd
exit 0
EOF
chmod 755 $OV/usr/local/sbin/bnasec-suid-repair
cat > $OV/etc/systemd/system/bnasec-suid-repair.service << 'EOF'
[Unit]
Description=BNAsec privileged binary permission repair
After=local-fs.target
ConditionPathExists=/usr/bin/sudo

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bnasec-suid-repair
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
ln -sf ../bnasec-suid-repair.service $OV/etc/systemd/system/multi-user.target.wants/bnasec-suid-repair.service

echo "=== 6) append override into squashfs ==="
rm -f $BASE/live/filesystem.squashfs
ln -f $SQ/fs.squashfs $BASE/live/filesystem.squashfs 2>/dev/null || cp $SQ/fs.squashfs $BASE/live/filesystem.squashfs
chmod u+w $BASE/live/filesystem.squashfs   # xorriso extracts read-only; append needs write
mksquashfs $OV $BASE/live/filesystem.squashfs \
  -comp zstd -Xcompression-level 6 -b 1M -all-root -no-recovery -no-progress 2>&1 | tail -2

echo "=== 7) verify ==="
unsquashfs -ll $BASE/live/filesystem.squashfs > $SQ/listing-fixed.txt 2>/dev/null
grep -E "usr/bin/(sudo|su|mount|umount|pkexec|passwd|wall)$|Xorg.wrap|unix_chkpwd$|dbus-daemon-launch-helper$|polkit-agent-helper-1$" $SQ/listing-fixed.txt
echo "--- group/gshadow/firstboot/suid-repair in image: ---"
grep -E "etc/(group|gshadow)$|bnasec-suid-repair|bnasec-firstboot" $SQ/listing-fixed.txt | head -8
echo "=== setuid count now: $(grep -cE '^-rws' $SQ/listing-fixed.txt) (was 0) ==="
