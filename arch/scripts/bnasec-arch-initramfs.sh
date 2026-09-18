#!/bin/bash
# BNAsec-Arch: custom initramfs — clean authoritative version.
# Stage: busybox+applets, udevadm/kmod/sfdisk/mke2fs/blkid + lib closures,
#        23 decompressed storage modules + depmod, /init with persistence.
set -u
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS
STAGE=$AB/initramfs-stage
KVER=$(ls $R/usr/lib/modules 2>/dev/null | grep -v extramodules | head -1)
[ -n "$KVER" ] || { echo "FATAL: no kernel modules tree"; exit 1; }
# busybox may live in /usr/bin (symlinked) or /usr/lib/initcpio (mkinitcpio-busybox)
if [ ! -f "$R/usr/bin/busybox" ] && [ -f "$R/usr/lib/initcpio/busybox" ]; then
  ln -sf ../lib/initcpio/busybox $R/usr/bin/busybox
fi
[ -f "$R/usr/bin/busybox" ] || { echo "FATAL: busybox missing in airootfs"; exit 1; }
echo "kernel: $KVER"
rm -rf $STAGE

# ---------- dirs ----------
mkdir -p $STAGE/usr/bin $STAGE/usr/lib $STAGE/usr/sbin $STAGE/etc \
         $STAGE/proc $STAGE/sys $STAGE/dev $STAGE/run $STAGE/newroot \
         $STAGE/mnt $STAGE/tmp $STAGE/run/bootmnt $STAGE/run/sfs \
         $STAGE/run/persist $STAGE/run/upper
rm -rf $STAGE/bin $STAGE/sbin $STAGE/lib $STAGE/lib64
ln -sfn usr/bin $STAGE/bin
ln -sfn usr/bin $STAGE/sbin
ln -sfn usr/lib $STAGE/lib
ln -sfn usr/lib $STAGE/lib64

# ---------- busybox + applets ----------
cp -L $R/usr/bin/busybox $STAGE/usr/bin/busybox
for a in sh mount umount mkdir mknod ln cat echo sed awk grep ls sleep \
         switch_root pivot_root mountpoint findfs udevadm modprobe mkfifo \
         mdev uname sync stat readlink head tail tr cut dirname basename \
         date chmod chown cp mv rm dmesg freeramdisk losetup swapon env \
         clear hexdump od printf test dd flock mkswap poweroff reboot blockdev; do
  ln -sf /usr/bin/busybox $STAGE/usr/bin/$a
done

# ---------- loader + real tools with lib closures ----------
cp -L $R/usr/lib/ld-linux-x86-64.so.2 $STAGE/usr/lib/
cp -L $R/usr/lib/libc.so.6 $STAGE/usr/lib/

copy_bin() { # copy_bin <path-under-R>
  local src="$R/$1" dst="$STAGE/$1"
  rm -f "$dst"
  mkdir -p "$(dirname "$dst")"
  cp -L "$src" "$dst"
  local libs
  libs=$(env LD_PRELOAD="$TOOLS/symlink-shim.so" "$R/lib64/ld-linux-x86-64.so.2" \
      --library-path "$R/usr/lib:$R/usr/lib/systemd:$R/lib" \
      --list "$src" 2>/dev/null | awk '/=> \//{print $3}' | grep -E '^/' | sort -u)
  for lib in $libs; do
    local rel="${lib#$R/}"
    [ "$rel" = "$lib" ] && continue
    [ -e "$STAGE/$rel" ] && continue
    mkdir -p "$(dirname "$STAGE/$rel")"
    cp -L "$lib" "$STAGE/$rel" 2>/dev/null || true
  done
}

copy_bin usr/bin/udevadm
copy_bin usr/bin/kmod
copy_bin usr/bin/sfdisk
copy_bin usr/bin/mke2fs
copy_bin usr/bin/blkid
ln -sf kmod $STAGE/usr/bin/modprobe
ln -sf kmod $STAGE/usr/bin/lsmod
cp $R/etc/mke2fs.conf $STAGE/etc/ 2>/dev/null

# ---------- kernel modules (decompressed) ----------
MODDIR=$STAGE/usr/lib/modules/$KVER
mkdir -p $MODDIR
MODS="isofs ext4 jbd2 mbcache crc32c_generic overlay squashfs loop zstd_compress xxhash \
      usb_storage uas sd_mod sr_mod scsi_mod ata_piix ahci libahci nvme nvme_core \
      virtio_blk virtio_scsi virtio-gpu xhci_pci xhci_hcd vfat fat exfat ntfs3 zram"
for m in $MODS; do
  src=$(find $R/usr/lib/modules/$KVER/kernel -name "$m.ko*" 2>/dev/null | head -1)
  [ -z "$src" ] && continue
  rel=${src#$R/usr/lib/modules/$KVER/}
  mkdir -p "$MODDIR/$(dirname $rel)"
  cp "$src" "$MODDIR/$rel"
done
DEP=$R/usr/lib/modules/$KVER/modules.dep
for f in $(find $MODDIR -name '*.ko*' 2>/dev/null); do
  rel=${f#$MODDIR/}
  for dep in $(grep -F "$rel:" "$DEP" 2>/dev/null | cut -d: -f2 | tr ',' ' '); do
    dep=$(echo $dep | xargs); [ -z "$dep" ] && continue
    dsrc="$R/usr/lib/modules/$KVER/$dep"
    [ -e "$dsrc" ] || continue
    ddst="$MODDIR/$dep"
    [ -e "$ddst" ] || { mkdir -p "$(dirname $ddst)"; cp "$dsrc" "$ddst"; }
  done
done
for f in $(find $MODDIR -name '*.ko.zst'); do
  $TOOLS/zstd-root/usr/bin/zstd -d -q -f "$f" -o "${f%.ko.zst}.ko"
  rm -f "$f"
done
echo "modules: $(find $MODDIR -name '*.ko' | wc -l) plain"
arch_run2 $R usr/bin/depmod -b "$STAGE" "$KVER" >/dev/null 2>&1 || true
if [ -s "$STAGE/lib/modules/$KVER/modules.dep" ]; then
  echo "modules.dep OK"
else
  echo "FATAL: modules.dep missing"; exit 1
fi

# ---------- THE INIT ----------
cat > $STAGE/init <<'INITEOF'
#!/usr/bin/busybox sh
export PATH=/usr/bin:/sbin:/bin
RES="/dev/console"
msg() { echo "[bnasec-init] $*" > $RES 2>/dev/null; }
dbgsh() { setsid sh -c "exec sh </dev/tty1 >/dev/tty1 2>&1" & }
fatal() { msg "FATAL: $* — debug shell on tty1"; dbgsh; sleep 100000; }

[ -d /proc ] || mkdir -p /proc
[ -d /sys ] || mkdir -p /sys
[ -d /dev ] || mkdir -p /dev
[ -d /run ] || mkdir -p /run
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mount -t tmpfs none /dev

CMDLINE=$(cat /proc/cmdline)
parse() { echo "$CMDLINE" | tr ' ' '\n' | grep "^$1=" | cut -d= -f2-; }
PERSIST=$(parse bnasec.persist); [ -z "$PERSIST" ] && PERSIST=1
BOOTLABEL=$(parse bnasec.label); [ -z "$BOOTLABEL" ] && BOOTLABEL="BNASECARCH"
ROOTSFS=$(parse bnasec.sfs); [ -z "$ROOTSFS" ] && ROOTSFS="arch/x86_64/airootfs.sfs"
msg "bnasec.persist=$PERSIST bootlabel=$BOOTLABEL"

for m in scsi_mod sd_mod sr_mod ata_piix ahci nvme virtio_blk virtio_scsi \
         usb_storage uas isofs ext4 overlay squashfs loop vfat exfat ntfs3 zram virtio_gpu; do
  err=$(/usr/bin/modprobe $m 2>&1) || case "$err" in
    *"not found"*) : ;;
    *) msg "modprobe $m FAILED: $err" ;;
  esac
done
sleep 2
msg "loaded=$(grep -c . /proc/modules 2>/dev/null) devnodes: $(ls /dev 2>/dev/null | grep -E '^(sd|sr|vd|nvme|mmc)' | tr '\n' ' ')"

bootdev=""
i=0
while [ $i -lt 20 ]; do
  for dev in /dev/sd[a-z][0-9]* /dev/vd[a-z][0-9]* /dev/mmcblk[0-9]*p[0-9]* /dev/nvme[0-9]*n[0-9]*p[0-9]* /dev/sr[0-9]* /dev/sd[a-z] /dev/vd[a-z] /dev/nvme[0-9]*n[0-9] /dev/mmcblk[0-9]*; do
    [ -b "$dev" ] || continue
    lbl=$(/usr/bin/blkid -o value -s LABEL "$dev" 2>/dev/null)
    if [ "$lbl" = "$BOOTLABEL" ]; then bootdev="$dev"; break; fi
  done
  [ -n "$bootdev" ] && break
  sleep 1
  i=$((i+1))
done
[ -n "$bootdev" ] || fatal "boot medium LABEL=$BOOTLABEL not found"
msg "boot medium: $bootdev"

persist_setup() {
  for t in /usr/bin/sfdisk /usr/bin/mke2fs /usr/bin/blkid /usr/bin/mount; do
    command -v "$t" >/dev/null 2>&1 || { msg "missing tool $t — persistence disabled"; return 1; }
  done
  if /usr/bin/blkid -o device -t LABEL=persistence >/dev/null 2>&1; then
    msg "persistence partition exists"
    return 0
  fi
  base=$(basename "$bootdev")
  disk=${base%[0-9]*}
  [ -e "/sys/class/block/$disk" ] || { msg "no disk node for $disk"; return 1; }
  rem=$(cat "/sys/class/block/$disk/removable" 2>/dev/null)
  if [ "$rem" != "1" ] && [ "$PERSIST" != "force" ]; then
    msg "/dev/$disk not removable — persistence skipped (bnasec.persist=force overrides)"
    return 1
  fi
  total=$(cat "/sys/class/block/$disk/size")
  lastend=0
  for p in /sys/class/block/${disk}*; do
    case "$(basename $p)" in ${disk}[0-9]*) ;; *) continue ;; esac
    [ -e "$p/start" ] || continue
    s=$(cat "$p/start"); z=$(cat "$p/size"); e=$((s + z))
    [ "$e" -gt "$lastend" ] && lastend=$e
  done
  msg "disk sectors=$total lastend=$lastend"
  start=$(( ((lastend + 2047) / 2048) * 2048 ))
  [ "$start" -le "$lastend" ] && start=$(( lastend + 1 ))
  size=$(( total - start - 100 ))
  if [ "$size" -lt $((2*1024*1024*1024/512)) ]; then
    msg "free space < 2GiB — persistence skipped"
    return 1
  fi
  if [ "$start" -le 2048 ] || [ "$start" -le "$lastend" ]; then
    msg "unsafe start=$start lastend=$lastend — ABORT"
    return 1
  fi
  pnum=1
  for p in /sys/class/block/${disk}*; do
    case "$(basename $p)" in ${disk}[0-9]*) ;; *) continue ;; esac
    [ -e "$p/dev" ] || continue
    n=$(basename "$p"); n=${n#$disk}
    case "$n" in (*[!0-9]*|'') continue ;; esac
    [ "$n" -ge "$pnum" ] && pnum=$(( n + 1 ))
  done
  msg "appending ${disk}${pnum}: start=$start size=$size"
  LBL=$(/usr/bin/sfdisk -d "/dev/$disk" 2>/dev/null | awk 'NR==1{print $2}')
  if [ "$LBL" = "gpt" ]; then PTYPE="type=linux"; else PTYPE="type=83"; fi
  printf 'start=%s, size=%s, %s\n' "$start" "$size" "$PTYPE" | \
    /usr/bin/sfdisk -f --append "/dev/$disk" >/dev/null 2>&1
  rc=$?
  [ $rc -eq 0 ] || msg "sfdisk rc=$rc — probing node anyway"
  # No BLKRRPART: it returns EBUSY with mounted partitions and invalidates the
  # isohybrid start=0 partition on re-read. Create the node ourselves instead.
  if [ ! -b "/dev/${disk}${pnum}" ]; then
    majmin=$(cat /sys/class/block/$disk/dev 2>/dev/null)
    maj=${majmin%%:*}; min=${majmin##*:}
    mknod "/dev/${disk}${pnum}" b "$maj" "$((min + pnum))" 2>/dev/null
  fi
  sleep 1
  [ -b "/dev/${disk}${pnum}" ] || { msg "cannot create partition node — ABORT"; return 1; }
  EXIST=$(/usr/bin/blkid -o value -s TYPE "/dev/${disk}${pnum}" 2>/dev/null)
  [ -n "$EXIST" ] && { msg "node has fs type=$EXIST — ABORT (no format)"; return 1; }
  msg "formatting /dev/${disk}${pnum} as ext4 LABEL=persistence"
  /usr/bin/mke2fs -L persistence -q -F "/dev/${disk}${pnum}" >/dev/null 2>&1 \
    || { msg "mke2fs FAILED — persistence off this boot"; return 1; }
  sync
  msg "persistence partition created"
  return 0
}

PMOUNTED=0
mkdir -p /run/persist
if [ "$PERSIST" != "0" ]; then
  persist_setup
  PDEV=$(/usr/bin/blkid -o device -t LABEL=persistence 2>/dev/null | head -1)
  if [ -n "$PDEV" ] && mount -t ext4 "$PDEV" /run/persist 2>/dev/null; then
    PMOUNTED=1
    msg "persistence mounted: $PDEV"
  else
    msg "persistence NOT mounted (RAM-only this boot)"
  fi
else
  msg "persistence disabled by cmdline"
fi

mkdir -p /run/bootmnt
mount -t iso9660 -o ro "$bootdev" /run/bootmnt 2>/dev/null \
  || { err=$(mount -o ro "$bootdev" /run/bootmnt 2>&1) || fatal "cannot mount boot medium: $err"; }
SFS="/run/bootmnt/$ROOTSFS"
[ -f "$SFS" ] || fatal "$SFS missing"
mkdir -p /run/sfs
mount -t squashfs -o ro "$SFS" /run/sfs || fatal "squashfs mount failed"
msg "airootfs.sfs mounted"

mkdir -p /newroot
if [ "$PMOUNTED" = "1" ]; then
  mkdir -p /run/persist/upper /run/persist/work /run/persist/persist-root
  if mount -t overlay overlay -o lowerdir=/run/sfs,upperdir=/run/persist/upper,workdir=/run/persist/work /newroot 2>/dev/null; then
    msg "PERSISTENT overlay active (changes stick across reboots)"
    mkdir -p /newroot/run/bnasec/persist
    mount --bind /run/persist/persist-root /newroot/run/bnasec/persist 2>/dev/null || true
  else
    msg "persistent overlay mount failed — falling back to tmpfs"
    umount /run/persist 2>/dev/null
    PMOUNTED=0
  fi
fi
if [ "$PMOUNTED" != "1" ]; then
  mkdir -p /run/upper
  mount -t tmpfs -o size=90% tmpfs /run/upper 2>/dev/null
  mkdir -p /run/upper/u /run/upper/w
  mount -t overlay overlay -o lowerdir=/run/sfs,upperdir=/run/upper/u,workdir=/run/upper/w /newroot \
    || fatal "tmpfs overlay failed"
  msg "RAM overlay active (nothing persists)"
fi

mkdir -p /newroot/run/bootmnt /newroot/run/bnasec
mount --move /run/bootmnt /newroot/run/bootmnt 2>/dev/null || mount -o bind /run/bootmnt /newroot/run/bootmnt 2>/dev/null || true
if [ "$PMOUNTED" = "1" ]; then
  mount --move /run/persist /newroot/run/bnasec/persist 2>/dev/null || true
fi
mount --move /proc /newroot/proc
mount --move /sys /newroot/sys
mount --move /dev /newroot/dev
mount --move /run /newroot/run 2>/dev/null || { mkdir -p /newroot/run; mount --move /run /newroot/run 2>/dev/null || true; }
msg "switch_root -> systemd"
exec switch_root /newroot /sbin/init
exec sh
INITEOF
chmod 755 $STAGE/init

# ---------- verify ----------
test -s $STAGE/init || { echo "FATAL: init missing"; exit 1; }
grep -q "persist_setup" $STAGE/init || { echo "FATAL: init truncated"; exit 1; }
test -s $STAGE/usr/lib/ld-linux-x86-64.so.2 || { echo "FATAL: loader missing"; exit 1; }
for t in sfdisk mke2fs blkid kmod; do test -s $STAGE/usr/bin/$t || { echo "FATAL: $t missing"; exit 1; }; done
du -sh $STAGE
echo "INITRAMFS STAGE READY (kver=$KVER)"
