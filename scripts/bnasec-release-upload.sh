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

echo "=== 3) update release body (final verified build) ==="
NEWSHA=$(awk '{print $1}' "$SHA")
api -X PATCH "https://api.github.com/repos/$REPO/releases/$RID" -d "{
  \"body\": \"BNAsec 2.0.0 — FINAL VERIFIED ISO (2026-09-15 15:51 build)\\n\\nDebian trixie live ISO: GNOME+GDM3 autologin bna, zsh+p10k, 6 pentest tools, hybrid BIOS+UEFI (Secure Boot OFF), plymouth splash, full-root persistence (auto-provisioned, ALL free space, same-boot activation).\\n\\nVERIFIED in QEMU on THIS build:\\n- BIOS boot: full boot to GDM, persistence overlay active on / (boot1 provision + boot2 proof)\\n- UEFI (OVMF) boot: full boot to GNOME desktop with BNAsec wallpaper + autologin\\n- 6 tools confirmed inside image: aircrack-ng, nmap, hydra, wpscan 3.8.28, dirb, sqlmap\\n- GRUB: quiet splash + bnasec theme + 3 entries (persistent / RAM-only / debug)\\n\\nSHA256: $NEWSHA\\n\\nFlash: dd if=bnasec-2.0.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync\\nSecure Boot: OFF. First boot auto-creates persistence partition with all free space.\"
}" | python3 -c "import json,sys;d=json.load(sys.stdin);print('  release updated:', d.get('name', d.get('message')))"

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
