#!/bin/bash
# BNAsec-Arch: custom initramfs with full-root persistence engine.
#
# Replaces mkinitcpio entirely (build-tree has no chroot; a hand-staged
# initramfs gives full control). Structure:
#   /init                      custom busybox script (mounts, persistence, switch_root)
#   /usr/bin/busybox + applets (hardlinks where possible, symlinks via shim)
#   /usr/bin/(udevd|udevadm|modprobe|sfdisk|mke2fs|blkid|mount...) + libs
#   /usr/lib/modules/<kver>/   storage modules only (isofs/ext4/overlay/...)
#   /etc/udev/rules.d/         udev persistent-storage rules for by-label
#
# Persistence (port of the PROVEN bnasec v2.0.0 engine + new guards):
#   boot1: find boot medium (LABEL=BNASECARCH) -> detect removable parent ->
#          append partition in free space (sfdisk --append) -> FORMAT GUARD
#          (refuse if any fs already present) -> mkfs.ext4 -L persistence ->
#          mount -> same-boot overlay (upper on the stick)
#   boot2+: mount existing persistence partition -> overlay upper/work
#   fallback: tmpfs upper (RAM-only session)
set -e
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS
STAGE=$AB/initramfs-stage
KVER=$(ls $R/usr/lib/modules | grep -v extramodules | head -1)
echo "kernel: $KVER"
rm -rf $STAGE; mkdir -p $STAGE

# ---------- helper: copy binary with its full lib closure ----------
copy_bin() { # copy_bin <src-in-R> <dst-relative>
  local src="$R/$1" dst="$STAGE/$2"
  rm -f "$dst"   # drop busybox applet symlink if present — real binary wins
  mkdir -p "$(dirname "$dst")"
  cp -L "$src" "$dst"
  # resolve deps via the arch loader's own readelf-less method: ldd needs
  # ld.so execution; use arch's ldd? busybox ldd not present. Use objdump-free
  # approach: run `ldd` via the arch runtime (it execs the loader itself).
  local libs
  libs=$(env LD_PRELOAD="$TOOLS/symlink-shim.so" "$R/lib64/ld-linux-x86-64.so.2" \
      --library-path "$R/usr/lib:$R/usr/lib/systemd:$R/lib" \
      --list "$src" 2>/dev/null | awk '/=> \//{print $3} /^\//{print $1}' | grep -E '^/' | sort -u)
  for lib in $libs; do
    local rel="${lib#/}"
    local target="$STAGE/$rel"
    [ -e "$target" ] && continue
    mkdir -p "$(dirname "$target")"
    # preserve symlink structure: copy chain (cp -L derefs; better keep names)
    if [ -L "$lib" ]; then
      cp -P "$lib" "$target" || cp -L "$lib" "$target"
    else
      cp "$lib" "$target"
    fi
  done
}

echo "=== 1) busybox + applets ==="
mkdir -p $STAGE/usr/bin $STAGE/usr/sbin $STAGE/bin $STAGE/sbin $STAGE/proc $STAGE/sys $STAGE/dev $STAGE/run $STAGE/newroot $STAGE/mnt $STAGE/tmp $STAGE/lib $STAGE/lib64 $STAGE/usr/lib $STAGE/etc
cp -L $R/usr/bin/busybox $STAGE/usr/bin/busybox
# applet links (shim makes symlinks legal); /init and /bin/sh are the critical ones
for a in sh mount umount mkdir mknod ln cat echo sed awk grep ls sleep switch_root \
         pivot_root mountpoint findfs blkid udevadm modprobe mkfifo mdev uname \
         sync stat readlink head tail tr cut dirname basename date chmod chown \
         cp mv rm dmesg freeramdisk losetup swapon env clear hexdump od printf \
         test [ dd flock mkswap poweroff reboot; do
  ln -sf /usr/bin/busybox $STAGE/usr/bin/$a
done
ln -sf /usr/bin/busybox $STAGE/init.tmp   # replaced by real init below
rm -f $STAGE/init.tmp
# usrmerge layout: /bin /sbin /lib /lib64 -> usr (symlinks; remove real dirs first)
rm -rf $STAGE/lib $STAGE/lib64
ln -sfn usr/bin $STAGE/bin; ln -sfn usr/bin $STAGE/sbin
ln -sfn usr/lib $STAGE/lib; ln -sfn usr/lib $STAGE/lib64
# real dynamic loader for copied binaries
mkdir -p $STAGE/usr/lib
for l in $R/usr/lib/ld-linux-x86-64.so.2 $R/usr/lib/libc.so.6; do cp -L "$l" $STAGE/usr/lib/; done

echo "=== 2) udev + modprobe + persistence tools ==="
copy_bin usr/lib/systemd/systemd-udevd usr/lib/systemd/systemd-udevd
copy_bin usr/bin/udevadm usr/bin/udevadm
copy_bin usr/bin/kmod usr/bin/kmod
copy_bin usr/bin/sfdisk usr/bin/sfdisk
copy_bin usr/bin/mke2fs usr/bin/mke2fs
copy_bin usr/bin/blkid usr/bin/blkid
ln -sf kmod $STAGE/usr/bin/modprobe 2>/dev/null || true
ln -sf kmod $STAGE/usr/bin/lsmod 2>/dev/null || true
# e2fsprogs needs its shared lib devices via mke2fs.conf
mkdir -p $STAGE/etc
cp $R/etc/mke2fs.conf $STAGE/etc/ 2>/dev/null || true

echo "=== 3) kernel modules (storage chain) ==="
MODDIR=$STAGE/usr/lib/modules/$KVER
mkdir -p $MODDIR
MODS="isofs ext4 jbd2 mbcache crc32c_generic overlay squashfs loop zstd_compress xxhash \
      usb_storage uas sd_mod sr_mod scsi_mod ata_piix ahci libahci nvme nvme_core \
      virtio virtio_ring virtio_pci virtio_blk virtio_scsi xhci_pci xhci_hcd vfat fat exfat ntfs3 zram"
# stage by FILENAME search (robust); builtins (bfq,usbcore,ehci,nls,zstd...) are in-kernel
STAGED=0
for m in $MODS; do
  src=$(find $R/usr/lib/modules/$KVER/kernel -name "$m.ko*" 2>/dev/null | head -1)
  [ -z "$src" ] && { echo "  (builtin or absent: $m)"; continue; }
  rel=${src#$R/usr/lib/modules/$KVER/}
  mkdir -p "$MODDIR/$(dirname $rel)"
  cp "$src" "$MODDIR/$rel"
  STAGED=$((STAGED+1))
done
# add dependencies of staged modules (from modules.dep of the full tree)
DEP=$R/usr/lib/modules/$KVER/modules.dep
[ -f "$DEP" ] || { echo "FATAL: modules.dep missing — run depmod first"; exit 1; }
for f in $(find $MODDIR -name '*.ko*' 2>/dev/null); do
  rel=${f#$MODDIR/}
  for dep in $(grep -F "$rel:" "$DEP" | cut -d: -f2 | tr ',' ' '); do
    dep=$(echo $dep | xargs); [ -z "$dep" ] && continue
    dsrc="$R/usr/lib/modules/$KVER/$dep"
    [ -e "$dsrc" ] || continue
    ddst="$MODDIR/$dep"
    [ -e "$ddst" ] || { mkdir -p "$(dirname $ddst)"; cp "$dsrc" "$ddst"; }
  done
done
echo "  modules staged: $(find $MODDIR -name '*.ko*' | wc -l)"
# regenerate dependency DB for the STAGED tree only (modprobe reads /lib/modules)
arch_run2 $R usr/bin/depmod -b "$STAGE" "$KVER" 2>&1 | tail -1 || true
[ -s "$STAGE/lib/modules/$KVER/modules.dep" ] && echo "  staged modules.dep OK ($(grep -c ':' $STAGE/lib/modules/$KVER/modules.dep) entries)"

echo "=== 4) udev rules for /dev/disk/by-label ==="
mkdir -p $STAGE/usr/lib/udev/rules.d $STAGE/etc/udev/rules.d
for r in 60-persistent-storage.rules 60-block.rules 64-btrfs.rules 50-udev-default.rules \
         60-cdrom_id.rules 75-probe_mtd.rules; do
  [ -f "$R/usr/lib/udev/rules.d/$r" ] && cp "$R/usr/lib/udev/rules.d/$r" $STAGE/usr/lib/udev/rules.d/
done
cp -r $R/usr/lib/udev/ata_id $STAGE/usr/lib/udev/ 2>/dev/null || true
cp -r $R/usr/lib/udev/scsi_id $STAGE/usr/lib/udev/ 2>/dev/null || true
cp -r $R/usr/lib/udev/cdrom_id $STAGE/usr/lib/udev/ 2>/dev/null || true

echo "=== 5) THE INIT (persistence engine) ==="
cat > $STAGE/init <<'INITEOF'
#!/usr/bin/busybox sh
# BNAsec-Arch custom init — busybox environment, persistence engine inside.
export PATH=/usr/bin:/sbin:/bin
RES="/dev/console"

msg() { echo "[bnasec-init] $*" > $RES 2>/dev/null; }

# --- minimal mounts ---
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

# --- udev coldplug ---
/lib/systemd/systemd-udevd --daemon --resolve-names=never 2>/dev/null \
  || /usr/lib/systemd/systemd-udevd --daemon --resolve-names=never 2>/dev/null \
  || msg "WARN: udevd start failed"
udevd_pid=$(pidof systemd-udevd | tr ' ' '\n' | head -1)
udevadm trigger --action=add --type=subsystems 2>/dev/null
udevadm trigger --action=add --type=devices 2>/dev/null
udevadm settle --timeout=12 2>/dev/null || sleep 3

# --- load key modules early (covers kernels without coldplug auto-load) ---
modprobe isofs 2>/dev/null; modprobe ext4 2>/dev/null; modprobe overlay 2>/dev/null
modprobe squashfs 2>/dev/null; modprobe loop 2>/dev/null
modprobe usb_storage 2>/dev/null; modprobe uas 2>/dev/null
modprobe nvme 2>/dev/null; modprobe virtio_pci 2>/dev/null; modprobe ahci 2>/dev/null
udevadm settle --timeout=8 2>/dev/null || sleep 2

# --- find boot medium by label ---
bootdev=""
i=0
while [ $i -lt 20 ]; do
  bootdev=$(blkid -o device -t LABEL="$BOOTLABEL" 2>/dev/null | head -1)
  [ -n "$bootdev" ] && break
  sleep 1
  udevadm settle --timeout=2 2>/dev/null
  i=$((i+1))
done
[ -n "$bootdev" ] || { msg "FATAL: boot medium LABEL=$BOOTLABEL not found"; exec sh; }
msg "boot medium: $bootdev"

mkdir -p /run/bootmnt
mount -t iso9660 -o ro "$bootdev" /run/bootmnt 2>/dev/null \
  || mount -o ro "$bootdev" /run/bootmnt \
  || { msg "FATAL: cannot mount boot medium"; exec sh; }
SFS="/run/bootmnt/$ROOTSFS"
[ -f "$SFS" ] || { msg "FATAL: $SFS missing"; exec sh; }

mkdir -p /run/sfs
mount -t squashfs -o ro "$SFS" /run/sfs || { msg "FATAL: squashfs mount failed"; exec sh; }
msg "airootfs.sfs mounted"

# ---------- persistence engine (port of proven bnasec logic + guards) ----------
persist_setup() {
  # requirements
  for t in sfdisk mke2fs blkid mount; do
    command -v "$t" >/dev/null 2>&1 || { msg "missing tool $t — persistence disabled"; return 1; }
  done
  # already present?
  if blkid -o device -t LABEL=persistence >/dev/null 2>&1; then
    msg "persistence partition exists"
    return 0
  fi
  # boot device parent (strip partition digit)
  base=$(basename "$bootdev")
  disk=${base%[0-9]*}
  [ -e "/sys/class/block/$disk" ] || { msg "no disk node for $disk"; return 1; }
  rem=$(cat "/sys/class/block/$disk/removable" 2>/dev/null)
  # allow force via cmdline; else require removable
  if [ "$rem" != "1" ] && [ "$PERSIST" != "force" ]; then
    msg "/dev/$disk not removable — persistence skipped (bnasec.persist=force to override)"
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
    msg "free space < 2GiB ($((size/2048))MiB) — persistence skipped"
    return 1
  fi
  if [ "$start" -le 2048 ] || [ "$start" -le "$lastend" ]; then
    msg "unsafe start=$start lastend=$lastend — ABORT, no changes"
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
  LBL=$(sfdisk -d "/dev/$disk" 2>/dev/null | awk 'NR==1{print $2}')
  if [ "$LBL" = "gpt" ]; then PTYPE="type=linux"; else PTYPE="type=83"; fi
  printf 'start=%s, size=%s, %s\n' "$start" "$size" "$PTYPE" | \
    sfdisk -f --append "/dev/$disk" >/dev/null 2>&1
  rc=$?
  [ $rc -eq 0 ] || msg "sfdisk rc=$rc — probing node anyway"
  partx -a "/dev/$disk" >/dev/null 2>&1 || true
  udevadm settle --timeout=10 2>/dev/null || sleep 2
  [ -b "/dev/${disk}${pnum}" ] || { msg "partition node missing — ABORT"; return 1; }
  # FORMAT GUARD: never format a partition that already has a filesystem
  EXIST=$(blkid -o value -s TYPE "/dev/${disk}${pnum}" 2>/dev/null)
  [ -n "$EXIST" ] && { msg "node has fs type=$EXIST — ABORT (no format)"; return 1; }
  msg "formatting /dev/${disk}${pnum} as ext4 LABEL=persistence"
  mke2fs -L persistence -q -F "/dev/${disk}${pnum}" >/dev/null 2>&1 \
    || { msg "mke2fs FAILED — persistence off this boot"; return 1; }
  sync
  msg "persistence partition created"
  return 0
}

PMOUNTED=0
mkdir -p /run/persist
if [ "$PERSIST" != "0" ]; then
  persist_setup
  PDEV=$(blkid -o device -t LABEL=persistence 2>/dev/null | head -1)
  if [ -n "$PDEV" ] && mount -t ext4 "$PDEV" /run/persist 2>/dev/null; then
    PMOUNTED=1
    msg "persistence mounted: $PDEV"
  else
    msg "persistence NOT mounted (RAM-only this boot)"
  fi
else
  msg "persistence disabled by cmdline"
fi

# ---------- assemble root overlay ----------
mkdir -p /newroot
if [ "$PMOUNTED" = "1" ]; then
  mkdir -p /run/persist/upper /run/persist/work /run/persist/persist-root
  if mount -t overlay overlay -o lowerdir=/run/sfs,upperdir=/run/persist/upper,workdir=/run/persist/work /newroot 2>/dev/null; then
    msg "PERSISTENT overlay active (changes stick across reboots)"
    mkdir -p /newroot/run/bnasec/persist
    mount --bind /run/persist/persist-root /newroot/run/bnasec/persist 2>/dev/null || true
  else
    msg "overlay mount failed — falling back to tmpfs"
    PMOUNTED=0
  fi
fi
if [ "$PMOUNTED" != "1" ]; then
  mkdir -p /run/upper /run/work
  mount -t tmpfs -o size=90% tmpfs /run/upper 2>/dev/null
  mkdir -p /run/upper/u /run/work/w
  mount -t overlay overlay -o lowerdir=/run/sfs,upperdir=/run/upper/u,workdir=/run/work/w /newroot \
    || { msg "FATAL: tmpfs overlay failed"; exec sh; }
  msg "RAM overlay active (nothing persists)"
fi

# carry boot media + persistence mount into the new root
mkdir -p /newroot/run/bootmnt /newroot/run/bnasec
mount --move /run/bootmnt /newroot/run/bootmnt 2>/dev/null || mount -o bind /run/bootmnt /newroot/run/bootmnt 2>/dev/null || true
if [ "$PMOUNTED" = "1" ]; then
  mount --move /run/persist /newroot/run/bnasec/persist 2>/dev/null || true
fi

# --- stop udev, move pseudo-fs, switch ---
[ -n "$udevd_pid" ] && kill "$udevd_pid" 2>/dev/null
udevadm control --exit 2>/dev/null
mount --move /proc /newroot/proc
mount --move /sys /newroot/sys
mount --move /dev /newroot/dev
mount --move /run /newroot/run 2>/dev/null || { mkdir -p /newroot/run; mount --move /run /newroot/run; }
msg "switch_root -> systemd"
exec switch_root /newroot /sbin/init
# never reached
exec sh
INITEOF
chmod 755 $STAGE/init
rm -f $STAGE/init.tmp 2>/dev/null || true

echo "=== 6) verify stage ==="
test -x $STAGE/init && echo "  init OK"
test -e $STAGE/lib64/ld-linux-x86-64.so.2 && echo "  loader path OK" || { echo "  loader MISSING"; ls $STAGE/lib64; }
test -e $STAGE/usr/bin/sfdisk && test -e $STAGE/usr/bin/mke2fs && test -e $STAGE/usr/bin/blkid && echo "  persist tools OK"
test -e $STAGE/lib/modules/$KVER/modules.dep && echo "  modules.dep OK"
du -sh $STAGE
echo "INITRAMFS STAGE READY at $STAGE (kver=$KVER)"
