#!/bin/bash
# BNAsec definitive setuid fix: tree -> fix -> fresh squashfs (space-guarded)
set -e
BASE=/home/z/my-project/bnasec-build
SQ=$BASE/sqfix
TREE=$SQ/tree
T=$BASE/tools-root
export PATH="$T/usr/bin:$T/usr/sbin:$T/bin:$PATH"
export LD_LIBRARY_PATH="$T/usr/lib/x86_64-linux-gnu:$T/lib/x86_64-linux-gnu"

dfguard() { local min=$1; local free=$(df --output=avail -B1 / | tail -1); [ "$free" -gt "$min" ] || { echo "FATAL: only ${free}B free, need >${min}B"; exit 1; }; }

echo "=== 1) extract full tree ==="
if [ -d $TREE ] && [ -f $TREE/usr/bin/sudo ]; then
  echo "tree already extracted — resuming"
else
  dfguard 2200000000
  rm -rf $TREE
  unsquashfs -q -d $TREE $SQ/fs.squashfs 2>&1 | tail -1
  rm -rf $TREE/usr_1 $TREE/etc_1   # pollution from failed append attempt
fi
echo "tree: $(find $TREE -type f | wc -l) files, $(du -sh $TREE | cut -f1)"
df -h / | tail -1

echo "=== 2) fix setuid/setgid bits ==="
for f in sudo su mount umount pkexec passwd chsh chfn gpasswd chage expiry fusermount3; do
  chmod 4755 $TREE/usr/bin/$f
done
chmod 4755 $TREE/usr/lib/xorg/Xorg.wrap
chmod 4755 $TREE/usr/lib/polkit-1/polkit-agent-helper-1
chmod 4754 $TREE/usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod 4754 $TREE/usr/sbin/unix_chkpwd
chmod 2755 $TREE/usr/bin/wall
N=$(find $TREE -xdev -perm /6000 -type f | wc -l)
echo "setuid/setgid files in tree: $N (expect 17)"
[ "$N" -eq 17 ] || { echo "FATAL: unexpected suid count"; find $TREE -xdev -perm /6000 -type f; exit 1; }

echo "=== 3) sudo group membership for bna ==="
sed -i 's/^sudo:x:27:$/sudo:x:27:bna/' $TREE/etc/group
grep -q '^sudo:.*bna' $TREE/etc/group || { echo "FATAL: group edit failed"; exit 1; }
grep '^sudo' $TREE/etc/group
sed -i 's/^sudo:\*::$/sudo:*::bna/' $TREE/etc/gshadow
grep -q '^sudo:.*bna' $TREE/etc/gshadow || { echo "FATAL: gshadow edit failed"; exit 1; }
grep '^sudo' $TREE/etc/gshadow

echo "=== 4) firstboot: add sudo group at runtime too ==="
cat > $TREE/usr/local/sbin/bnasec-firstboot << 'EOF'
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
chmod 755 $TREE/usr/local/sbin/bnasec-firstboot

echo "=== 5) boot-time suid self-repair insurance unit ==="
cat > $TREE/usr/local/sbin/bnasec-suid-repair << 'EOF'
#!/bin/sh
# BNAsec: ensure privileged binaries keep their setuid bits (idempotent)
for f in sudo su mount umount pkexec passwd chsh chfn gpasswd chage expiry fusermount3; do
  [ -f /usr/bin/$f ] && chmod 4755 /usr/bin/$f
done
[ -f /usr/bin/wall ] && chmod 2755 /usr/bin/wall
[ -f /usr/lib/xorg/Xorg.wrap ] && chmod 4755 /usr/lib/xorg/Xorg.wrap
[ -f /usr/lib/polkit-1/polkit-agent-helper-1 ] && chmod 4755 /usr/lib/polkit-1/polkit-agent-helper-1
[ -f /usr/lib/dbus-1.0/dbus-daemon-launch-helper ] && chmod 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper
[ -f /usr/sbin/unix_chkpwd ] && chmod 4754 /usr/sbin/unix_chkpwd
exit 0
EOF
chmod 755 $TREE/usr/local/sbin/bnasec-suid-repair
cat > $TREE/etc/systemd/system/bnasec-suid-repair.service << 'EOF'
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
mkdir -p $TREE/etc/systemd/system/multi-user.target.wants
ln -sf ../bnasec-suid-repair.service $TREE/etc/systemd/system/multi-user.target.wants/bnasec-suid-repair.service

echo "=== 6) fresh squashfs ==="
rm -f $SQ/fs.squashfs $BASE/live/filesystem.squashfs   # tree is now the source of truth — free space first
dfguard 1500000000
mksquashfs $TREE $BASE/live/filesystem.squashfs \
  -comp zstd -Xcompression-level 6 -b 1M -all-root -noappend \
  -e boot -wildcards -e 'var/cache/apt/*' 'var/lib/apt/lists/*' 2>&1 | tail -1
ls -la $BASE/live/
df -h / | tail -1

echo "=== 7) free tree, verify new image ==="
rm -rf $TREE
dfguard 1000000000
unsquashfs -ll $BASE/live/filesystem.squashfs > $SQ/listing-final.txt 2>/dev/null
echo "suid count: $(grep -cE '^-rws' $SQ/listing-final.txt) (expect 16)"
grep -E "usr/bin/sudo$" $SQ/listing-final.txt
echo "suid-repair unit: $(grep -c 'bnasec-suid-repair' $SQ/listing-final.txt) entries (expect 2)"
df -h / | tail -1
echo "=== DONE — run bnasec-iso-final.sh next ==="
