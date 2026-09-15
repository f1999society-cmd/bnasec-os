#!/bin/bash
# Upload the fixed ISO + sha256 to GitHub Release v2.0.0 (replace old assets)
set -e
TOKEN=$(cat /home/z/my-project/.gh-token)
REPO="f1999society-cmd/bnasec-os"
ISO=/home/z/my-project/bnasec-build/bnasec-2.0.0-amd64.iso
SHA=/home/z/my-project/bnasec-build/bnasec-2.0.0-amd64.iso.sha256

api() { curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

echo "=== 1) get release id ==="
RID=$(api "https://api.github.com/repos/$REPO/releases/tags/v2.0.0" | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
echo "release id: $RID"

echo "=== 2) delete old assets ==="
for AID in $(api "https://api.github.com/repos/$REPO/releases/$RID/assets" | python3 -c "
import json,sys
for a in json.load(sys.stdin): print(a['id'])"); do
  echo "  deleting asset $AID"
  api -X DELETE "https://api.github.com/repos/$REPO/releases/assets/$AID" -o /dev/null
done

echo "=== 3) update release body (fixed build) ==="
api -X PATCH "https://api.github.com/repos/$REPO/releases/$RID" -d '{
  "body": "BNAsec 2.0.0 — REBUILT FIXED ISO (2026-09-15)\n\nDebian trixie live ISO: GNOME+GDM3 autologin bna, zsh+p10k, 6 pentest tools, hybrid BIOS+UEFI (Secure Boot OFF), plymouth splash with spinner, full-root persistence (auto-provisioned, ALL free space, same-boot activation).\n\nVERIFIED in QEMU: BIOS boot to GNOME desktop, UEFI boot with splash, persistence auto-provisioning + 2-boot proof.\n\nChanges vs 2026-09-15 02:52 build:\n- persistence bug FIXED (initramfs same-boot provisioning + hardened systemd fallback + sfdisk installed)\n- initramfs fully rebuilt (complete lib closures, ELF loader, busybox intact)\n- 696 broken host-path symlinks repaired (CA certs/PAM/ALSA/GDM)\n- GRUB El Torito cdboot fix (BIOS boot now works, was VGA garbage)\n\nSHA256: f0e6dff72130eea1902597531bba9d7866a741e94039cb7a9b233391b92fd1d2\n\nFlash: dd if=bnasec-2.0.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync\nSecure Boot: OFF. First boot auto-creates persistence partition with all free space."
}' | python3 -c "import json,sys;d=json.load(sys.stdin);print('  release updated:', d.get('name', d.get('message')))"

echo "=== 4) upload ISO ==="
SZ=$(stat -c %s "$ISO")
curl -s -H "Authorization: token $TOKEN" -H "Content-Type: application/octet-stream" \
  --data-binary @"$ISO" \
  "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=bnasec-2.0.0-amd64.iso" | \
  python3 -c "import json,sys;d=json.load(sys.stdin);print('  ISO:', d.get('state'), d.get('size'), d.get('message',''))"

echo "=== 5) upload sha256 ==="
curl -s -H "Authorization: token $TOKEN" -H "Content-Type: text/plain" \
  --data-binary @"$SHA" \
  "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=bnasec-2.0.0-amd64.iso.sha256" | \
  python3 -c "import json,sys;d=json.load(sys.stdin);print('  SHA:', d.get('state'), d.get('message',''))"

echo "=== done ==="
