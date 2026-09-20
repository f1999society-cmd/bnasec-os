#!/usr/bin/env python3
"""Probe the decompressed size of a remote .zst by parsing its frame header (Range request)."""
import struct, sys, urllib.request, json

TOKEN = open('/home/z/my-project/.gh-token').read().strip()
API = 'https://api.github.com/repos/f1999society-cmd/ml4w-arch-usb/releases'

# resolve the asset id for the .zst
areq = urllib.request.Request(API, headers={'Authorization': f'Bearer {TOKEN}',
                                            'Accept': 'application/vnd.github+json'})
with urllib.request.urlopen(areq, timeout=30) as r:
    rels = json.load(r)
asset_id = next(a['id'] for rel in rels for a in rel['assets']
                if a['name'].endswith('.img.zst'))
print('asset id:', asset_id)
URL = f'{API}/assets/{asset_id}'

req = urllib.request.Request(URL, headers={
    'Authorization': f'Bearer {TOKEN}',
    'Accept': 'application/octet-stream',
    'Range': 'bytes=0-63',
})
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        head = r.read(64)
        print('HTTP status:', r.status)
except Exception as e:
    sys.exit(f'download failed: {e}')

if len(head) < 6 or head[:4] != b'\x28\xb5\x2f\xfd':
    sys.exit(f'not a zstd frame start (got {len(head)} bytes: {head[:8].hex()})')

fhd = head[4]
fcs_flag = (fhd >> 6) & 0b11
single_segment = (fhd >> 5) & 1
dict_id_flag = fhd & 0b11

pos = 5
if not single_segment:
    pos += 1  # window descriptor
dict_sizes = {0: 0, 1: 1, 2: 2, 3: 4}
pos += dict_sizes[dict_id_flag]

fcs_sizes = {0: (0 if not single_segment else -1), 1: 2, 2: 4, 3: 8}
n = fcs_sizes[fcs_flag]
if n == -1:
    print('FCS encoded as window size (single-segment, flag 0) — cannot parse exactly')
elif n == 0:
    print('Frame content size: not stored in header')
else:
    raw = head[pos:pos + n]
    if len(raw) < n:
        sys.exit(f'need more bytes ({pos+n})')
    if n == 2:
        size = struct.unpack('<H', raw)[0] + 256
    elif n == 4:
        size = struct.unpack('<I', raw)[0]
    else:
        size = struct.unpack('<Q', raw)[0]
    print(f'DECOMPRESSED SIZE: {size} bytes = {size/1024**3:.2f} GiB')
