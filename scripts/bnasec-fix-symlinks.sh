#!/bin/bash
# Repair ALL symlinks in the BNAsec rootfs that point to the build host.
# fakechroot stored absolute symlink targets as host paths during Stage B.
# Fix: strip the "/home/z/my-project/bnasec-build/rootfs" prefix, keep the
# in-rootfs path; verify the target resolves; map through usrmerge if needed.
set -u
ROOTFS=/home/z/my-project/bnasec-build/rootfs
PREFIX=/home/z/my-project/bnasec-build/rootfs
FIXED=0
UNFIXED=0

cd "$ROOTFS" || exit 1

find . -type l 2>/dev/null | while read -r l; do
  t=$(readlink "$l")
  case "$t" in
    "$PREFIX"/*)
      new="${t#"$PREFIX"}"
      # ensure the target exists inside the rootfs; try usrmerge variants
      if [ -e ".$new" ] || [ -L ".$new" ]; then
        :
      else
        alt=""
        case "$new" in
          /lib/*)  alt="/usr/lib${new#/lib}" ;;
          /bin/*)  alt="/usr/bin${new#/bin}" ;;
          /sbin/*) alt="/usr/sbin${new#/sbin}" ;;
        esac
        if [ -n "$alt" ] && { [ -e ".$alt" ] || [ -L ".$alt" ]; }; then
          new="$alt"
        fi
      fi
      ln -sfn "$new" "$l" && echo "FIXED: $l -> $new" || echo "UNFIXED: $l"
      ;;
  esac
done > /tmp/symlink-repair.log 2>&1

grep -c "^FIXED" /tmp/symlink-repair.log
grep "^UNFIXED" /tmp/symlink-repair.log | head -5
echo "---display-manager explicit fix---"
ls -la usr/lib/systemd/system/gdm.service >/dev/null 2>&1 && \
  ln -sfn /usr/lib/systemd/system/gdm.service etc/systemd/system/display-manager.service && \
  ls -la etc/systemd/system/display-manager.service
echo "---residual bad symlinks---"
find . -type l 2>/dev/null | while read -r l; do
  t=$(readlink "$l")
  case "$t" in /home/z/*) echo "STILL-BAD: $l -> $t";; esac
done | head -5
echo "(end)"
