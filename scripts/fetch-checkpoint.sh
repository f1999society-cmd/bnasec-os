#!/bin/bash
# Robust checkpoint download from GitHub release (asset API -> signed URL -> file)
set -e
TOKEN=$(cat /home/z/my-project/.gh-token)
OUT=/home/z/my-project/checkpoint.squashfs
AID=$(curl -sf -H "Authorization: token $TOKEN" https://api.github.com/repos/f1999society-cmd/bnasec-os/releases/tags/checkpoint | python3 -c "import json,sys;print(json.load(sys.stdin)['assets'][0]['id'])")
echo "asset id: $AID"
# GitHub asset download: request octet-stream, follow redirect
curl -sL --retry 5 --retry-delay 3 -C - \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/octet-stream" \
  -o "$OUT" \
  "https://api.github.com/repos/f1999society-cmd/bnasec-os/releases/assets/$AID"
SZ=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
echo "downloaded: $SZ bytes"
[ "$SZ" -gt 1400000000 ] && echo "CHECKPOINT OK" || { echo "CHECKPOINT TOO SMALL"; exit 1; }
