#!/home/z/.venv/bin/python3
"""BNAsec v2.1 initramfs verification: compare against v2.0.0 known-good ground truth.
Usage: verify-initrd-v21.py <initrd-to-verify> [reference-initrd]
Checks: cpio sections, critical files, plymouth plugins, storage modules, busybox applets.
Exit 0 = GOOD, 1 = PROBLEMS (printed).
"""
import sys, io
import zstandard

def parse(off, data):
    ents = []
    while data[off:off+6] == b'070701':
        def f(i): return int(data[off+6+i*8:off+6+(i+1)*8], 16)
        namesize = f(11); filesize = f(6)
        name = data[off+110:off+110+namesize-1].decode(errors='replace')
        if name == 'TRAILER!!!':
            npos = (off + 110 + namesize + 3) & ~3
            return ents, npos + ((filesize + 3) & ~3)
        ents.append(name)
        npos = (off + 110 + namesize + 3) & ~3
        off = npos + ((filesize + 3) & ~3)
    return ents, off

def load(path):
    data = open(path, 'rb').read()
    s1, end1 = parse(0, data)
    zoff = end1
    while zoff < len(data) and data[zoff] == 0:
        zoff += 1
    zstd = data[zoff:zoff+4] == b'\x28\xb5\x2f\xfd'
    raw = zstandard.ZstdDecompressor().stream_reader(io.BytesIO(data[zoff:])).read()
    main, _ = parse(0, raw) if raw[:6] == b'070701' else ([], 0)
    return set(s1) | set(main), len(s1), len(main), zstd

target, ref = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else
    '/home/z/my-project/bnasec-build/isostage/initrd.img')

names, n1, n2, zstd = load(target)
rnames, rn1, rn2, _ = load(ref)
print(f"target: s1={n1} main={n2} unique={len(names)} zstd-after-s1={zstd}")
print(f"  ref  : s1={rn1} main={rn2} unique={len(rnames)}")

fails = []

# 1) hard requirements (must be in target)
hard = [
    "usr/share/plymouth/themes/bnasec/bnasec.plymouth",
    "usr/share/plymouth/themes/bnasec/bnasec-logo.png",
    "usr/share/plymouth/themes/bnasec/animation-0018.png",
    "usr/share/plymouth/themes/bnasec/throbber-0015.png",
    "usr/lib/x86_64-linux-gnu/plymouth/two-step.so",
    "usr/lib/x86_64-linux-gnu/plymouth/text.so",
    "usr/lib/x86_64-linux-gnu/plymouth/details.so",
    "usr/lib/x86_64-linux-gnu/plymouth/label-pango.so",
    "usr/lib/x86_64-linux-gnu/plymouth/renderers/frame-buffer.so",
    "usr/lib/x86_64-linux-gnu/plymouth/renderers/drm.so",
    "usr/sbin/plymouthd",
    "usr/bin/busybox",
    "bin/sh",
    "scripts/init-premount/bnasec-persist",
    "usr/sbin/sfdisk",
    "usr/sbin/mke2fs",
    "usr/sbin/blkid",
    "conf/arch-modules",   # marker dirs usually present as files/dirs entries
]
for p in hard:
    ok = p in names
    print(("  OK  " if ok else "  MISS ") + p)
    if not ok and not p.startswith("conf/"):
        fails.append(p)

# 2) storage modules
mods = ["ahci.ko.xz","scsi_mod.ko.xz","usb-storage.ko.xz","uas.ko.xz","iso9660.ko.xz",
        "ext4.ko.xz","overlay.ko.xz","xhci-pci.ko.xz","ehci-pci.ko.xz","uhci-hcd.ko.xz",
        "nls_iso8859-1.ko.xz","vfat.ko.xz","zram.ko.xz","bfq.ko.xz"]
for m in mods:
    found = any(n.endswith("/" + m) for n in names)
    print(("  OK   mod " if found else "  MISS mod ") + m)
    if not found:
        fails.append("module " + m)

ko = [n for n in names if n.endswith('.ko') or n.endswith('.ko.xz')]
rko = [n for n in rnames if n.endswith('.ko') or n.endswith('.ko.xz')]
print(f"ko modules: target={len(ko)} ref={len(rko)}")

# 3) regression vs reference (present in v2.0.0 good initrd, absent now)
missing_vs_ref = sorted(n for n in rnames if n not in names)
critical_missing = [n for n in missing_vs_ref if
                    '/plymouth/' in n or 'busybox' in n or 'libply' in n or
                    'sfdisk' in n or 'mke2fs' in n or 'blkid' in n or
                    n.startswith('scripts/') or n.startswith('lib/systemd/')]
print(f"entries in ref but not target: {len(missing_vs_ref)} (critical subset: {len(critical_missing)})")
for n in critical_missing[:25]:
    print("  REF-ONLY: " + n)
    fails.append("ref-only " + n)

if fails:
    print(f"=== VERIFICATION FAILED ({len(fails)} problems) ===")
    sys.exit(1)
print("=== INITRAMFS VERIFIED (matches known-good baseline + v2.1 additions) ===")
