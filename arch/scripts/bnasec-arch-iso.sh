#!/bin/bash
# BNAsec-Arch: pack initramfs + assemble hybrid BIOS+UEFI ISO (proven recipe).
set -e
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS
STAGE=$AB/initramfs-stage
ISO=$AB/isostage
KVER=$(ls $R/usr/lib/modules | grep -v extramodules | head -1)
OUT=$AB/bnasec-arch-1.0.0-amd64.iso

echo "=== 1) pack initramfs (newc cpio, zstd) ==="
rm -f $STAGE/../initramfs-linux.img
( cd $STAGE && find . -print0 | LC_ALL=C sort -z | cpio -0 -o -H newc --quiet ) > $AB/initramfs-linux.cpio
ls -la $AB/initramfs-linux.cpio
$TOOLS/zstd-root/usr/bin/zstd -q -3 -f $AB/initramfs-linux.cpio -o $AB/initramfs-linux.img
rm $AB/initramfs-linux.cpio
$TOOLS/zstd-root/usr/bin/zstd -t $AB/initramfs-linux.img
test -s $AB/initramfs-linux.img || { echo "FATAL: initramfs empty"; exit 1; }
ls -la $AB/initramfs-linux.img

echo "=== 2) stage ISO tree ==="
rm -rf $ISO; mkdir -p $ISO/boot/grub/fonts $ISO/arch/x86_64 $ISO/EFI/boot
VLN=$R/boot/vmlinuz-linux
[ -e "$VLN" ] || VLN=$R/usr/lib/modules/$KVER/vmlinuz   # hooks disabled: /boot copy may not exist
cp "$VLN" $ISO/boot/vmlinuz-linux
mkdir -p $R/boot
[ "$VLN" = "$R/boot/vmlinuz-linux" ] || cp "$VLN" $R/boot/vmlinuz-linux
cp $AB/initramfs-linux.img $ISO/boot/initramfs-linux.img
ln $AB/airootfs.sfs $ISO/arch/x86_64/airootfs.sfs 2>/dev/null || cp $AB/airootfs.sfs $ISO/arch/x86_64/airootfs.sfs
cp $ARCH_ROOT/usr/share/grub/unicode.pf2 $ISO/boot/grub/fonts/ 2>/dev/null || find $ARCH_ROOT/usr/share/grub -name unicode.pf2 -exec cp {} $ISO/boot/grub/fonts/ \;

echo "=== 3) grub.cfg + theme (Catppuccin Mocha) ==="
cat > $ISO/boot/grub/grub.cfg <<'EOF'
# BNAsec Arch — GRUB (Catppuccin Mocha)
loadfont unicode
insmod all_video
insmod gfxterm
insmod png
insmod jpeg
insmod search_label
insmod search_fs_uuid
insmod part_gpt
insmod part_msdos
terminal_output gfxterm
set gfxmode=auto
set gfxpayload=keep

set menu_color_normal=light-gray/black
set menu_color_highlight=white/light-magenta
set color_normal=white/black
set color_highlight=black/light-magenta

set default=0
set timeout=8

menuentry "BNAsec Arch — Hyprland (persistent)" {
    linux /boot/vmlinuz-linux quiet loglevel=3 console=tty0 console=ttyS0,115200 zswap.enabled=0 bnasec.persist=1 bnasec.label=BNASECARCH
    initrd /boot/initramfs-linux.img
}
menuentry "BNAsec Arch — RAM-only session (no persistence)" {
    linux /boot/vmlinuz-linux quiet loglevel=3 console=tty0 console=ttyS0,115200 zswap.enabled=0 bnasec.persist=0 bnasec.label=BNASECARCH
    initrd /boot/initramfs-linux.img
}
menuentry "BNAsec Arch — verbose boot (debug)" {
    linux /boot/vmlinuz-linux loglevel=7 console=tty0 console=ttyS0,115200 bnasec.persist=1 bnasec.label=BNASECARCH
    initrd /boot/initramfs-linux.img
}
EOF

echo "=== 4) GRUB core images (early cfg: search by volume label) ==="
mkdir -p $AB/grub-build
cat > $AB/grub-build/early.cfg <<'EOF'
search.fs_label BNASECARCH root
set prefix=($root)/boot/grub
EOF
arch_run2 $ARCH_ROOT usr/bin/grub-mkimage -O i386-pc-eltorito \
  -d "$ARCH_ROOT/usr/lib/grub/i386-pc" -o $AB/grub-build/bios.img \
  -p /boot/grub -c $AB/grub-build/early.cfg \
  biosdisk iso9660 part_gpt part_msdos search_label search_fs_uuid search_fs_file \
  all_video gfxterm font png jpeg video_bochs video_cirrus \
  linux linux16 normal configfile boot cat echo ls minicmd test sleep gzio
arch_run2 $ARCH_ROOT usr/bin/grub-mkimage -O x86_64-efi \
  -d "$ARCH_ROOT/usr/lib/grub/x86_64-efi" -o $AB/grub-build/bootx64.efi \
  -p /boot/grub -c $AB/grub-build/early.cfg \
  iso9660 part_gpt part_msdos search_label search_fs_uuid search_fs_file \
  all_video gfxterm font png jpeg \
  linux normal configfile boot cat echo ls minicmd test sleep gzio
ls -la $AB/grub-build/

echo "=== 5) ESP image (efi.img) ==="
rm -f $AB/grub-build/efi.img
arch_run2 $ARCH_ROOT usr/bin/mformat -C -i $AB/grub-build/efi.img -f 2880 ::
arch_run2 $ARCH_ROOT usr/bin/mmd -i $AB/grub-build/efi.img ::/EFI ::/EFI/boot
arch_run2 $ARCH_ROOT usr/bin/mcopy -i $AB/grub-build/efi.img $AB/grub-build/bootx64.efi ::/EFI/boot/BOOTX64.EFI
arch_run2 $ARCH_ROOT usr/bin/mcopy -i $AB/grub-build/efi.img $AB/grub-build/bootx64.efi ::/EFI/boot/grubx64.efi

echo "=== 6) xorriso hybrid build (proven layout) ==="
cp $AB/grub-build/bios.img $ISO/boot/grub/bios.img
rm -f $OUT
arch_run2 $ARCH_ROOT usr/bin/xorriso -as mkisofs \
  -volid BNASECARCH \
  -rational-rock -joliet \
  -isohybrid-mbr "$ARCH_ROOT/usr/lib/grub/i386-pc/boot_hybrid.img" \
  --grub2-boot-info \
  -c /boot.catalog \
  -b /boot/grub/bios.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e --interval:appended_partition_2:all:: \
    -no-emul-boot \
  -isohybrid-gpt-basdat \
  -append_partition 2 0xef $AB/grub-build/efi.img \
  -o $OUT \
  $ISO 2>&1 | tail -3

echo "=== 7) verify ==="
ls -la $OUT
arch_run2 $ARCH_ROOT usr/bin/xorriso -indev $OUT -report_el_torito as_mkisofs 2>&1 | head -5
sha256sum $OUT | tee $OUT.sha256
echo "ISO READY: $OUT"
df -h / | tail -1
