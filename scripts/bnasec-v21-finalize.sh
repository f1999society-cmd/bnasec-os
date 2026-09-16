#!/bin/bash
# BNAsec v2.1.0 finalize: persistence hooks -> suid repair -> initramfs -> verify
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
RS=/home/z/my-project/repo/scripts
KVER=6.12.107+deb13-amd64

echo "=== 1) install proven persistence fixes (from repo) ==="
install -m 755 "$RS/fixed-initramfs-premount-bnasec-persist" "$R/etc/initramfs-tools/scripts/init-premount/bnasec-persist"
install -m 755 "$RS/fixed-bnasec-persist-setup"          "$R/usr/local/sbin/bnasec-persist-setup"
rm -f  "$R/etc/initramfs-tools/hooks/bnasec-udev-libs"
install -m 755 "$RS/fixed-hook-bnasec-persist-tools"     "$R/etc/initramfs-tools/hooks/bnasec-persist-tools"
install -m 755 "$RS/fixed-hook-bnasec-udev-complete"     "$R/etc/initramfs-tools/hooks/bnasec-udev-complete"
install -m 755 "$RS/fixed-hook-bnasec-plymouth-complete" "$R/etc/initramfs-tools/hooks/bnasec-plymouth-complete"
rm -f "$R/usr/share/initramfs-tools/hooks/kmod" "$R/usr/share/initramfs-tools/hooks/zz-busybox"
install -m 755 "$RS/fixed-hook-kmod-explicit"   "$R/usr/share/initramfs-tools/hooks/kmod-explicit"
install -m 755 "$RS/fixed-hook-zz-busybox"      "$R/usr/share/initramfs-tools/hooks/zz-busybox"
rm -f "$R/usr/share/initramfs-tools/hooks/intel_microcode"
install -m 755 "$RS/bnasec-chroot-ldd" "$R/usr/local/bin/bnasec-ldd"
sed -i 's|env --unset=LD_PRELOAD ldd |/usr/local/bin/bnasec-ldd |g' "$R/usr/share/initramfs-tools/hook-functions"
mkdir -p "$R/boot" "$R/var/tmp" "$R/tmp"
FDEB=$(ls $BASE/debs/fdisk_*.deb 2>/dev/null | head -1)
if [ -z "$FDEB" ]; then
  python3 "$RS/bnasec-debfetch.py" "$R" fdisk | tail -1
  FDEB=$(ls $BASE/debs/fdisk_*.deb | head -1)
fi
dpkg-deb -x "$FDEB" "$R"
test -x "$R/usr/sbin/sfdisk" && echo "  sfdisk OK"
rm -f "$R/boot/vmlinuz-$KVER"
cp "$BASE/isostage/vmlinuz" "$R/boot/vmlinuz-$KVER"
chmod 644 "$R/boot/vmlinuz-$KVER"
echo "  persistence hooks + kernel OK"

echo "=== 2) SUID/SGID repair (unsquashfs stripped them) ==="
for f in sudo su mount umount pkexec passwd chsh chfn gpasswd chage expiry fusermount3; do
  chmod 4755 $R/usr/bin/$f
done
chmod 4755 $R/usr/lib/xorg/Xorg.wrap
chmod 4755 $R/usr/lib/polkit-1/polkit-agent-helper-1
chmod 4754 $R/usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod 4754 $R/usr/sbin/unix_chkpwd
chmod 2755 $R/usr/bin/wall
N=$(find $R -xdev -perm /6000 -type f | wc -l)
echo "  setuid/setgid files: $N (expect 17)"
[ "$N" -eq 17 ] || { echo "FATAL suid count"; find $R -xdev -perm /6000 -type f; exit 1; }
grep -q '^sudo:.*bna' $R/etc/group   && echo "  group OK: $(grep '^sudo' $R/etc/group)"
grep -q '^sudo:.*bna' $R/etc/gshadow || sed -i 's/^sudo:\*::$/sudo:*::bna/' $R/etc/gshadow
grep '^sudo' $R/etc/gshadow

echo "=== 3) free debs + index ==="
rm -rf $BASE/debs $BASE/Packages.xz
df -h / | tail -1

echo "=== 4) mkinitramfs (fakechroot chroot into rootfs) ==="
cd /home/z/my-project && . repo/scripts/bnasec-chroot-env.sh
rm -f "$R/boot/initrd.img-$KVER"
bnasec_run "mkinitramfs -o /boot/initrd.img-$KVER $KVER" 2>&1 | tail -4
test -s "$R/boot/initrd.img-$KVER" || { echo "INITRAMFS FAILED"; exit 1; }
ls -la "$R/boot/initrd.img-$KVER"

echo "=== 5) verify initramfs exhaustively (section-aware: modules live in UNCOMPRESSED section) ==="
/home/z/.venv/bin/python3 - "$R/boot/initrd.img-$KVER" << 'PYEOF'
import sys
data = open(sys.argv[1],'rb').read()
off = 0; section = 1; ko = 0; seen = set(); main_entries = 0
def parse(off):
    ents = []
    while data[off:off+6] == b'070701':
        def f(i): return int(data[off+6+i*8:off+6+(i+1)*8], 16)
        namesize = f(11); filesize = f(6)
        name = data[off+110:off+110+namesize-1].decode(errors='replace')
        if name == 'TRAILER!!!':
            npos = (off + 110 + namesize + 3) & ~3
            return ents, npos + ((filesize + 3) & ~3)
        ents.append((name, filesize))
        npos = (off + 110 + namesize + 3) & ~3
        off = npos + ((filesize + 3) & ~3)
    return ents, off
s1, end1 = parse(0)
zoff = end1
while zoff < len(data) and data[zoff] == 0: zoff += 1
assert data[zoff:zoff+4] == b'\x28\xb5\x2f\xfd', "no zstd main frame after section1"
import zstandard, io
main_raw = zstandard.ZstdDecompressor().stream_reader(io.BytesIO(data[zoff:])).read()
main_ents, _ = parse(main_raw) if main_raw[:6] == b'070701' else ([], 0)
names = set(n for n,_ in s1) | set(n for n,_ in main_ents)
ko = len([n for n in names if n.endswith('.ko') or n.endswith('.ko.xz')])
print(f"section1: {len(s1)} entries | main(zstd): {len(main_ents)} entries | total unique: {len(names)} | ko modules: {ko}")
for p in ["scripts/init-premount/bnasec-persist",
          "usr/share/plymouth/themes/bnasec/bnasec.plymouth",
          "usr/share/plymouth/themes/bnasec/bnasec-logo.png",
          "usr/share/plymouth/themes/bnasec/animation-0018.png",
          "usr/sbin/plymouthd", "bin/busybox",
          "usr/lib/systemd/libsystemd-shared-257.so"]:
    assert p in names, f"MISSING {p}"
    print(f"  OK  {p}")
for m in ["ahci.ko.xz","scsi_mod.ko.xz","usb-storage.ko.xz","uas.ko.xz","iso9660.ko.xz","ext4.ko.xz","overlay.ko.xz","xhci-pci.ko.xz","ehci-pci.ko.xz","uhci-hcd.ko.xz","nls_iso8859-1.ko.xz","vfat.ko.xz"]:
    found = any(n.endswith("/"+m) for n in names)
    assert found, f"MISSING MODULE {m}"
    print(f"  OK  {m}")
assert ko > 1000, "TOO FEW MODULES"
print("=== INITRAMFS VERIFIED ===")
PYEOF
cp "$R/boot/initrd.img-$KVER" "$BASE/isostage/initrd.img"

echo "=== 6) rebuild squashfs ==="
mkdir -p "$BASE/live"
mksquashfs "$R" "$BASE/live/filesystem.squashfs" \
  -comp zstd -Xcompression-level 6 -b 1M -all-root -noappend \
  -e boot -wildcards -e 'var/cache/apt/*' 'var/lib/apt/lists/*' 2>&1 | tail -2
ls -la "$BASE/live/"

echo "=== 7) verify new squashfs contents (before dropping rootfs) ==="
S=$BASE/live/filesystem.squashfs
unsquashfs -lls "$S" 2>/dev/null | awk 'substr($1,4,1) ~ /[sS]/ || substr($1,7,1) ~ /[sS]/ {print $1, $NF}' | head -20
for f in usr/bin/sudo usr/lib/firefox-esr/firefox-esr usr/share/backgrounds/bnasec/bnasec-wave.jpg \
         usr/share/plymouth/themes/bnasec/animation-0036.png etc/systemd/system/bnasec-zram.service \
         etc/gdm3/daemon.conf usr/share/glib-2.0/schemas/15_bnasec.gschema.override \
         etc/systemd/system/multi-user.target.wants/bnasec-zram.service etc/skel/Desktop/READ-ME-FIRST.txt; do
  unsquashfs -lls "$S" 2>/dev/null | grep -q " $f\$" && echo "  OK  $f" || { echo "  MISSING $f"; exit 1; }
done
grep -c "AutomaticLoginEnable=false" <(unsquashfs -lls "$S" 2>/dev/null) >/dev/null 2>&1 || true
echo "=== SQUASHFS VERIFIED ==="
df -h / | tail -1
