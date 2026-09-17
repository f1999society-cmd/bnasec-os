#!/bin/bash
# Upload ISO + sha256 to the EXISTING GitHub Release v2.1.1 (id 390347634)
set -e
TOKEN=$(cat /home/z/my-project/.gh-token)
REPO="f1999society-cmd/bnasec-os"
ISO=/home/z/my-project/bnasec-build/bnasec-2.1.1-amd64.iso
SHA=/home/z/my-project/bnasec-build/bnasec-2.1.1-amd64.iso.sha256
RID=390347634

api() { curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

echo "=== 1) release check ==="
api "https://api.github.com/repos/$REPO/releases/$RID" | python3 -c "
import json,sys
r=json.load(sys.stdin)
print('release:', r.get('name'), '| assets:', [(a['name'], a['state']) for a in r.get('assets',[])])"

echo "=== 2) delete incomplete assets if any ==="
for AID in $(api "https://api.github.com/repos/$REPO/releases/$RID/assets" | python3 -c "
import json,sys
for a in json.load(sys.stdin):
    if a['state'] != 'uploaded': print(a['id'])"); do
  echo "  deleting asset $AID"
  api -X DELETE "https://api.github.com/repos/$REPO/releases/assets/$AID" -o /dev/null
done

echo "=== 3) upload ISO (throttled) ==="
curl -s --limit-rate 6M -o /tmp/upload-iso.json -w "HTTP %{http_code} (%{time_total}s)\n" \
  -H "Authorization: token $TOKEN" -H "Content-Type: application/octet-stream" \
  --data-binary @"$ISO" \
  "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=bnasec-2.1.1-amd64.iso"
python3 -c "import json;d=json.load(open('/tmp/upload-iso.json'));print('asset:', d.get('name'), d.get('size'), d.get('state') or d.get('message'))"

echo "=== 4) upload sha256 ==="
curl -s -o /tmp/upload-sha.json \
  -H "Authorization: token $TOKEN" -H "Content-Type: text/plain" \
  --data-binary @"$SHA" \
  "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=bnasec-2.1.1-amd64.iso.sha256"
python3 -c "import json;d=json.load(open('/tmp/upload-sha.json'));print('asset:', d.get('name'), d.get('state') or d.get('message'))"

echo "=== 5) verify ==="
api "https://api.github.com/repos/$REPO/releases/$RID" | python3 -c "
import json,sys
r=json.load(sys.stdin)
for a in r.get('assets',[]):
    print('  asset:', a['name'], a['size'], a['state'])"
