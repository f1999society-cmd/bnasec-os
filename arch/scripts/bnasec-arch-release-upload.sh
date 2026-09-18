#!/bin/bash
# Upload ISO parts + fresh sha256 to GitHub release arch-v1.0.0.
set -e
TOKEN=$(cat /home/z/my-project/.gh-token)
REPO="f1999society-cmd/bnasec-os"
REL_ID=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/repos/$REPO/releases/tags/arch-v1.0.0 | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
echo "release id: $REL_ID"

upload() {  # upload <file> <name>
  local F=$1 N=$2
  echo "uploading $N ($(stat -c%s $F) bytes)..."
  for i in 1 2 3; do
    CODE=$(curl -s -o /tmp/up-resp.json -w "%{http_code}" \
      -X POST -H "Authorization: token $TOKEN" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @$F \
      "https://uploads.github.com/repos/$REPO/releases/$REL_ID/assets?name=$N")
    if [ "$CODE" = "201" ]; then echo "  OK ($CODE)"; return 0; fi
    echo "  attempt $i failed ($CODE):"; head -c 300 /tmp/up-resp.json; echo
    sleep 15
  done
  return 1
}

# delete stale sha256 asset if present
OLD_ID=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/repos/$REPO/releases/$REL_ID/assets | python3 -c "
import json,sys
for a in json.load(sys.stdin):
    if a['name'] == 'bnasec-arch-1.0.0-amd64.iso.sha256':
        print(a['id']); break")
if [ -n "$OLD_ID" ]; then
  curl -s -X DELETE -H "Authorization: token $TOKEN" https://api.github.com/repos/$REPO/releases/assets/$OLD_ID
  echo "deleted stale sha256 asset $OLD_ID"
fi

upload /home/z/my-project/arch-build/bnasec-arch-1.0.0-amd64.iso.sha256 bnasec-arch-1.0.0-amd64.iso.sha256
upload /home/z/my-project/arch-build/bnasec-arch-1.0.0-amd64.iso-part-00 bnasec-arch-1.0.0-amd64.iso-part-00
upload /home/z/my-project/arch-build/bnasec-arch-1.0.0-amd64.iso-part-01 bnasec-arch-1.0.0-amd64.iso-part-01
echo "ALL UPLOADS DONE"
curl -s -H "Authorization: token $TOKEN" https://api.github.com/repos/$REPO/releases/$REL_ID/assets | python3 -c "
import json,sys
for a in json.load(sys.stdin): print(a['name'], a['size'], a['state'])"
