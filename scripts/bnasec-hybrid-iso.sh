#!/bin/bash
# BNAsec manual hybrid ISO build (BIOS+UEFI, replaces flaky grub-mkrescue path)
# Layout: MBR(grub boot_hybrid) + El Torito BIOS + appended ESP(part2) +
#         El Torito UEFI -> part2 + GPT protective/basdat entries
set -e
BASE=/home/z/my-project/bnasec-build
T=$BASE/tools-root
GRUBB=$T/usr/lib/grub
OUT=$BASE/bnasec-2.0.0-amd64.iso
W=/tmp/bnasec-hybrid
STAGE=$W/isodir

export PATH="$T/usr/bin:$T/usr/sbin:$T/sbin:$T/bin:$PATH"
export LD_LIBRARY_PATH="$T/usr/lib/x86_64-linux-gnu:$T/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

echo "=== 1) BIOS core image (El Torito + isohybrid) ==="
mkdir -p $W
cat > $W/early-bios.cfg << 'EOF'
search.fs_label BNASEC root
set prefix=($root)/boot/grub
EOF
# El Torito boot REQUIRES the cdboot flavor (2048B CD-sector loader).
# i386-pc-eltorito = cdboot.img + core (same recipe grub-mkrescue uses).
# A plain i386-pc image shows VGA garbage after "Booting from DVD/CD".
grub-mkimage -O i386-pc-eltorito -d $GRUBB/i386-pc -o $W/bios.img \
  -p /boot/grub -c $W/early-bios.cfg \
  biosdisk iso9660 part_gpt part_msdos search_fs_file search_label search_fs_uuid \
  all_video gfxterm font png jpeg video_bochs video_cirrus \
  linux linux16 normal configfile boot cat echo ls minicmd test sleep gzio
ls -la $W/bios.img

echo "=== 2) UEFI bootx64.efi ==="
cat > $W/early-efi.cfg << 'EOF'
search.fs_label BNASEC root
set prefix=($root)/boot/grub
EOF
grub-mkimage -O x86_64-efi -d $GRUBB/x86_64-efi -o $W/bootx64.efi \
  -p /boot/grub -c $W/early-efi.cfg \
  iso9660 part_gpt part_msdos search_fs_file search_label search_fs_uuid \
  all_video gfxterm font png jpeg \
  linux normal configfile boot cat echo ls minicmd test sleep gzio
ls -la $W/bootx64.efi

echo "=== 3) ESP image (efi.img, FAT, 4MB) ==="
rm -f $W/efi.img
mformat -C -i $W/efi.img -f 2880 -v BNASECEFI ::
mmd -i $W/efi.img ::/EFI ::/EFI/BOOT
mcopy -i $W/efi.img $W/bootx64.efi ::/EFI/BOOT/BOOTX64.EFI
mmd -i $W/efi.img ::/EFI/debian 2>/dev/null || true
mcopy -i $W/efi.img $W/bootx64.efi ::/EFI/debian/grubx64.efi 2>/dev/null || true
ls -la $W/efi.img
mdir -i $W/efi.img ::/EFI/BOOT 2>/dev/null || true

echo "=== 4) stage ISO tree (graft from existing staging if present) ==="
if [ -d "$BASE/minichroot/isodir" ]; then
  rm -rf $STAGE; cp -al "$BASE/minichroot/isodir" $STAGE
elif [ -d "$W/isodir-keep" ]; then
  rm -rf $STAGE; cp -al "$W/isodir-keep" $STAGE
elif [ -f "$BASE/live/filesystem.squashfs" ]; then
  rm -rf $STAGE; mkdir -p $STAGE/live $STAGE/boot/grub/themes/bnasec $STAGE/boot/grub/fonts
  ln "$BASE/live/filesystem.squashfs" $STAGE/live/filesystem.squashfs
  ln "$BASE/isostage/vmlinuz" "$BASE/isostage/initrd.img" $STAGE/live/
  cp "$BASE/assets/grub-bg.png" $STAGE/boot/grub/themes/bnasec/bg.png
  cp "$BASE"/assets/menu_*.png $STAGE/boot/grub/themes/bnasec/
  cp "$T/usr/share/grub/unicode.pf2" $STAGE/boot/grub/fonts/
  cp "$BASE/assets/iso-grub.cfg" $STAGE/boot/grub/grub.cfg
  cp "$BASE/assets/iso-theme.txt" $STAGE/boot/grub/themes/bnasec/theme.txt
else
  echo "no staging source"; exit 1
fi
test -f $STAGE/live/vmlinuz && test -f $STAGE/live/initrd.img && test -f $STAGE/live/filesystem.squashfs && test -f $STAGE/boot/grub/grub.cfg || { echo "staging incomplete"; exit 1; }
# El Torito BIOS image must live inside the ISO tree
cp $W/bios.img $STAGE/boot/grub/bios.img

echo "=== 5) xorriso hybrid build ==="
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
  $STAGE 2>&1 | tail -4

echo "=== 6) verify ==="
file $OUT
xorriso -indev $OUT -report_el_torito 2>&1 | grep -E "El Torito|Boot record|No El" | head -3
xorriso -indev $OUT -report_system_area 2>&1 | grep -iE "gpt guideline|partition 2|protective|grub2-mbr|boot info" | head -8
python3 - << 'PYEOF'
import struct, uuid
f = open('/home/z/my-project/bnasec-build/bnasec-2.0.0-amd64.iso','rb')
f.seek(1024)
g = f.read(8)
print("GPT@LBA2:", g)
if g == b'EFI PART':
    hdr = f.read(92)
    sig, rev, hsz, hcrc, res, cur, alt, fu, lu, guid, ptbl, n, psz, crc = struct.unpack('<8sIII4sQQQQ16sQIII', hdr)
    f.seek(ptbl*512)
    for i in range(n):
        e = f.read(psz)
        first, last = struct.unpack('<QQ', e[32:48])
        name = e[56:128].decode('utf-16-le').rstrip('\x00')
        if first:
            print(f"  GPT part{i+1}: first={first} sizeMB={(last-first+1)*512//1048576} name='{name}' type={str(uuid.UUID(bytes_le=e[0:16]))[:8]}")
f.seek(0); mbr = f.read(512)
import struct
for i in range(4):
    e = mbr[446+i*16:446+(i+1)*16]
    t = e[4]
    if t: print(f"  MBR part{i+1}: type={hex(t)}")
f.seek(17*2048)
print("sector17 (should be El Torito BRD):", f.read(7))
PYEOF
echo "=== ISO built: $OUT ==="
ls -la $OUT
