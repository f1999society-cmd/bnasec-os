#!/bin/bash
# Space-safe ISO build: stage via hardlinks, free live copy, then xorriso
set -e
BASE=/home/z/my-project/bnasec-build
T=$BASE/tools-root
GRUBB=$T/usr/lib/grub
OUT=$BASE/bnasec-2.0.0-amd64.iso
W=/tmp/bnasec-hybrid
STAGE=$W/isodir

export PATH="$T/usr/bin:$T/usr/sbin:$T/sbin:$T/bin:$PATH"
export LD_LIBRARY_PATH="$T/usr/lib/x86_64-linux-gnu:$T/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

rm -rf $W && mkdir -p $W
cat > $W/early-bios.cfg << 'EOF'
search.fs_label BNASEC root
set prefix=($root)/boot/grub
EOF
cat > $W/early-efi.cfg << 'EOF'
search.fs_label BNASEC root
set prefix=($root)/boot/grub
EOF

echo "=== grub images ==="
grub-mkimage -O i386-pc-eltorito -d $GRUBB/i386-pc -o $W/bios.img \
  -p /boot/grub -c $W/early-bios.cfg \
  biosdisk iso9660 part_gpt part_msdos search_fs_file search_label search_fs_uuid \
  all_video gfxterm font png jpeg video_bochs video_cirrus \
  linux linux16 normal configfile boot cat echo ls minicmd test sleep gzio
grub-mkimage -O x86_64-efi -d $GRUBB/x86_64-efi -o $W/bootx64.efi \
  -p /boot/grub -c $W/early-efi.cfg \
  iso9660 part_gpt part_msdos search_fs_file search_label search_fs_uuid \
  all_video gfxterm font png jpeg \
  linux normal configfile boot cat echo ls minicmd test sleep gzio

echo "=== ESP image ==="
mformat -C -i $W/efi.img -f 2880 -v BNASECEFI ::
mmd -i $W/efi.img ::/EFI ::/EFI/BOOT
mcopy -i $W/efi.img $W/bootx64.efi ::/EFI/BOOT/BOOTX64.EFI
mmd -i $W/efi.img ::/EFI/debian 2>/dev/null || true
mcopy -i $W/efi.img $W/bootx64.efi ::/EFI/debian/grubx64.efi 2>/dev/null || true

echo "=== stage (hardlinks) ==="
rm -rf $STAGE
mkdir -p $STAGE/live $STAGE/boot/grub/themes/bnasec $STAGE/boot/grub/fonts
ln "$BASE/live/filesystem.squashfs" $STAGE/live/filesystem.squashfs
ln "$BASE/isostage/vmlinuz" "$BASE/isostage/initrd.img" $STAGE/live/
cp "$BASE/assets/grub-bg.png" $STAGE/boot/grub/themes/bnasec/bg.png
cp "$BASE"/assets/menu_*.png $STAGE/boot/grub/themes/bnasec/
cp "$T/usr/share/grub/unicode.pf2" $STAGE/boot/grub/fonts/
cp "$BASE/assets/iso-grub.cfg" $STAGE/boot/grub/grub.cfg
cp "$BASE/assets/iso-theme.txt" $STAGE/boot/grub/themes/bnasec/theme.txt
cp $W/bios.img $STAGE/boot/grub/bios.img
test -f $STAGE/live/vmlinuz && test -f $STAGE/live/initrd.img && \
test -f $STAGE/live/filesystem.squashfs && test -f $STAGE/boot/grub/grub.cfg

echo "=== free live copy (hardlink keeps data) ==="
SQ_INODE=$(stat -c %i "$BASE/live/filesystem.squashfs" 2>/dev/null || echo 0)
ST_INODE=$(stat -c %i "$STAGE/live/filesystem.squashfs" 2>/dev/null || echo 1)
[ "$SQ_INODE" = "$ST_INODE" ] || { echo "hardlink mismatch — NOT freeing"; exit 1; }
rm -f "$BASE/live/filesystem.squashfs"
df -h / | tail -1

echo "=== xorriso ==="
rm -f $OUT
xorriso -as mkisofs \
  -volid BNASEC \
  -rational-rock -joliet \
  -isohybrid-mbr $GRUBB/i386-pc/boot_hybrid.img \
  --grub2-boot-info \
  -c /boot.catalog \
  -b /boot/grub/bios.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e --interval:appended_partition_2:all:: \
    -no-emul-boot \
  -isohybrid-gpt-basdat \
  -append_partition 2 0xef $W/efi.img \
  -o $OUT \
  $STAGE 2>&1 | tail -3

echo "=== verify ==="
file $OUT
rm -rf $W
ls -la $OUT
df -h / | tail -1
