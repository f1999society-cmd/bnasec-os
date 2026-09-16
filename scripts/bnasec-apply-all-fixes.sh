#!/bin/bash
# BNAsec: apply ALL post-checkpoint fixes to a freshly restored rootfs.
# (checkpoint predates this session's fixes; this re-applies them all)
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
S=/home/z/my-project/scripts
KVER=6.12.107+deb13-amd64

echo "=== 1) install hardened hooks + provisioners ==="
install -m 755 $S/fixed-initramfs-premount-bnasec-persist $R/etc/initramfs-tools/scripts/init-premount/bnasec-persist
install -m 755 $S/fixed-bnasec-persist-setup          $R/usr/local/sbin/bnasec-persist-setup
rm -f  $R/etc/initramfs-tools/hooks/bnasec-udev-libs
install -m 755 $S/fixed-hook-bnasec-persist-tools     $R/etc/initramfs-tools/hooks/bnasec-persist-tools
install -m 755 $S/fixed-hook-bnasec-udev-complete     $R/etc/initramfs-tools/hooks/bnasec-udev-complete
install -m 755 $S/fixed-hook-bnasec-plymouth-complete $R/etc/initramfs-tools/hooks/bnasec-plymouth-complete
rm -f  $R/usr/share/initramfs-tools/hooks/kmod $R/usr/share/initramfs-tools/hooks/zz-busybox
install -m 755 $S/fixed-hook-kmod-explicit  $R/usr/share/initramfs-tools/hooks/kmod-explicit
install -m 755 $S/fixed-hook-zz-busybox     $R/usr/share/initramfs-tools/hooks/zz-busybox
rm -f  $R/usr/share/initramfs-tools/hooks/intel_microcode
install -m 755 $S/zzz-bnasec-closure-fix    $R/etc/initramfs-tools/hooks/zzz-bnasec-closure-fix
install -m 755 $S/bnasec-chroot-ldd         $R/usr/local/bin/bnasec-ldd
sed -i 's|env --unset=LD_PRELOAD ldd |/usr/local/bin/bnasec-ldd |g' $R/usr/share/initramfs-tools/hook-functions

echo "=== 2) fdisk (sfdisk) ==="
FDEB=$BASE/debs/fdisk_2.41.5-0+deb13u1_amd64.deb
mkdir -p $BASE/debs
[ -f "$FDEB" ] || curl -fsSL -o "$FDEB" "http://deb.debian.org/debian/pool/main/u/util-linux/fdisk_2.41.5-0+deb13u1_amd64.deb"
$BASE/tools-root/usr/bin/dpkg-deb -x "$FDEB" $R
test -x $R/usr/sbin/sfdisk && echo "  sfdisk OK"

echo "=== 3) kernel ==="
KDEB=$BASE/debs/linux-image-${KVER}_6.12.107-1_amd64.deb
mkdir -p $R/boot
[ -f "$KDEB" ] || curl -fsSL -o "$KDEB" "http://deb.debian.org/debian/pool/main/l/linux-signed-amd64/linux-image-${KVER}_6.12.107-1_amd64.deb"
rm -rf /tmp/kx && mkdir /tmp/kx
$BASE/tools-root/usr/bin/dpkg-deb -x "$KDEB" /tmp/kx
cp /tmp/kx/boot/vmlinuz-$KVER $R/boot/
cp /tmp/kx/boot/vmlinuz-$KVER $BASE/isostage/vmlinuz
rm -rf /tmp/kx
echo "  kernel OK"

echo "=== 4) repair fakechroot host-path symlinks ==="
bash $S/bnasec-fix-symlinks.sh 2>&1 | tail -3

echo "=== 5) rebuild initramfs ==="
cd /home/z/my-project && . scripts/bnasec-chroot-env.sh
rm -f $R/boot/initrd.img-$KVER
bnasec_run "unset ROOT R; mkinitramfs -o /boot/initrd.img-$KVER $KVER" 2>&1 | grep -E "zzz-closure|live-boot:" | tail -2
test -s $R/boot/initrd.img-$KVER || { echo "INITRAMFS FAILED"; exit 1; }
cp $R/boot/initrd.img-$KVER $BASE/isostage/initrd.img
echo "  initrd OK: $(du -h $R/boot/initrd.img-$KVER | cut -f1)"

echo "=== 6) sanity: gdm unit + tools ==="
readlink $R/etc/systemd/system/display-manager.service
for t in usr/bin/nmap usr/bin/aircrack-ng usr/bin/hydra usr/bin/sqlmap usr/bin/dirb usr/local/bin/wpscan; do
  test -e $R/$t && echo "  OK $t" || { echo "  MISSING $t"; exit 1; }
done
echo "=== ALL FIXES APPLIED ==="
