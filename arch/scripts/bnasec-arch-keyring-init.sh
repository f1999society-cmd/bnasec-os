#!/bin/bash
# Initialize a pacman keyring (import Arch keys + ultimate ownertrust).
# Usage: bnasec-arch-keyring-init.sh <keyring-dir>
set -e
source /home/z/my-project/arch-build/env.sh
KR="$1"
[ -d "$KR" ] || { echo "usage: $0 <keyring-dir>"; exit 1; }
mkdir -p "$KR"; chmod 700 "$KR"

run_gpg() { arch_run "" usr/bin/gpg --homedir "$KR" "$@"; }

echo "[keyring] importing archlinux.gpg ..."
run_gpg --batch --import "$ARCH_ROOT/usr/share/pacman/keyrings/archlinux.gpg" 2>&1 | tail -1 || true
echo "[keyring] importing revoked list ..."
run_gpg --batch --import "$ARCH_ROOT/usr/share/pacman/keyrings/archlinux-revoked" 2>&1 | tail -1 || true

echo "[keyring] setting ultimate ownertrust on all keys ..."
FPRS=$(run_gpg --with-colons --list-keys | awk -F: '$1=="fpr"{print $10}')
N=0
for f in $FPRS; do
  echo "$f:6:" >> "$KR/.ownertrust.tmp"
  N=$((N+1))
done
run_gpg --import-ownertrust "$KR/.ownertrust.tmp"
rm -f "$KR/.ownertrust.tmp"
echo "[keyring] $N keys trusted. verify test:"
FPR1=$(echo "$FPRS" | head -1)
run_gpg --list-keys "$FPR1" >/dev/null && echo "[keyring] OK"
