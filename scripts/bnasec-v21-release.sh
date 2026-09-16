#!/bin/bash
# Create GitHub Release v2.1.0 and upload ISO + sha256
set -e
TOKEN=$(cat /home/z/my-project/.gh-token)
REPO="f1999society-cmd/bnasec-os"
ISO=/home/z/my-project/bnasec-build/bnasec-2.1.0-amd64.iso
SHA=/home/z/my-project/bnasec-build/bnasec-2.1.0-amd64.iso.sha256

api() { curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

echo "=== 1) create release v2.1.0 ==="
NEWSHA=$(awk '{print $1}' "$SHA")
RID=$(api -X POST "https://api.github.com/repos/$REPO/releases" -d "{
  \"tag_name\": \"v2.1.0\",
  \"target_commitish\": \"main\",
  \"name\": \"BNAsec 2.1.0 — Secure · Stable · Firefox\",
  \"body\": \"BNAsec 2.1.0 (2026-09-16 build)\\n\\n**NEW vs 2.0.0**\\n- SECURITY: autologin REMOVED — boot requires password login (user: bna, password: bnasec — CHANGE IT with 'passwd' on first login). GRUB now passes live-config.noautologin so the login screen always appears.\\n- STABILITY: zram 4G compressed swap (zstd, priority 100) + tuned sysctl + BFQ scheduler BAKED IN and auto-starting at boot (verified in boot log: 'Adding 4194300k swap on /dev/zram0. Priority:100'). No more freeze/force-quit dialogs on low-RAM machines.\\n- Firefox ESR preinstalled and set as default browser.\\n- New boot splash: BNAsec dragon logo (from 1.jpg) with animated loading bar + throbber (plymouth two-step).\\n- Wallpapers: BNAsec Wave (2.jpg) as default, BNAsec Red Moon (3.jpg) selectable in Settings → Appearance → Background (or right-click desktop → Change Background).\\n- READ-ME-FIRST.txt on the desktop with credentials + tips.\\n\\nKEPT FROM 2.0.0\\n- All 17 setuid bits fixed, bna in sudo group (sudo works out of the box)\\n- 6 tools: aircrack-ng, nmap, hydra, wpscan 3.8.28, dirb, sqlmap\\n- zsh + powerlevel10k, dark theme, hostname bnasec\\n- Hybrid BIOS+UEFI boot (Secure Boot OFF), full-root persistence auto-provisioned on first boot\\n\\nVERIFIED IN QEMU ON THIS EXACT BUILD\\n- BIOS boot → plymouth splash → zram swap active → GDM password login → desktop (password tested by automated keyboard injection)\\n- UEFI (OVMF) boot → GDM password login\\n\\nSHA256: $NEWSHA\\n\\nFlash: dd if=bnasec-2.1.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync\\nNote: the login password protects against casual USB snooping; the persistence partition itself is not yet encrypted (LUKS planned for 2.2).\\nFirst boot note: keep the stick in the same USB port — persistence binds to the device that provisioned it.\"
}" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('id') or d)")
echo "release id: $RID"
[ "$RID" -gt 0 ] 2>/dev/null || { echo "release create failed"; exit 1; }

echo "=== 2) upload ISO (~1.93GB, be patient) ==="
curl -s -H "Authorization: token $TOKEN" -H "Content-Type: application/octet-stream" \
  --data-binary @"$ISO" \
  "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=bnasec-2.1.0-amd64.iso" | \
  python3 -c "import json,sys;d=json.load(sys.stdin);print('  ISO:', d.get('state'), d.get('size'), d.get('message',''))"

echo "=== 3) upload sha256 ==="
curl -s -H "Authorization: token $TOKEN" -H "Content-Type: text/plain" \
  --data-binary @"$SHA" \
  "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=bnasec-2.1.0-amd64.iso.sha256" | \
  python3 -c "import json,sys;d=json.load(sys.stdin);print('  SHA:', d.get('state'), d.get('message',''))"

echo "=== 4) verify release assets ==="
api "https://api.github.com/repos/$REPO/releases/tags/v2.1.0" | python3 -c "
import json,sys
r=json.load(sys.stdin)
print('release:', r['name'], '| id', r['id'])
for a in r['assets']: print('  asset:', a['name'], a['size'], a['state'])
"
echo "=== done ==="
