#!/usr/bin/env python3
"""BNAsec deb fetcher: resolve packages from FULL trixie Packages index -> pool download -> dpkg -x.
Usage: bnasec-debfetch.py <target-dir> <pkg1> [pkg2 ...]
"""
import lzma, sys, os, urllib.request, subprocess, pathlib

BASE = pathlib.Path("/home/z/my-project/bnasec-build")
IDX = BASE / "Packages.xz"
IDX_URLS = [
    "http://deb.debian.org/debian/dists/trixie/main/binary-amd64/Packages.xz",
]

def load_index():
    if not IDX.exists() or IDX.stat().st_size < 100000:
        for u in IDX_URLS:
            try:
                print(f"fetching full Packages.xz ...")
                urllib.request.urlretrieve(u, IDX)
                break
            except Exception as e:
                print(f"  failed {u}: {e}")
        else:
            sys.exit("no Packages index could be fetched")
    raw = lzma.decompress(IDX.read_bytes()).decode("utf-8", "replace")
    pkgs = {}
    for block in raw.split("\n\n"):
        if not block.strip():
            continue
        fields = {}
        key = None
        for line in block.split("\n"):
            if line.startswith(" ") and key:
                continue
            if ":" in line:
                key, _, val = line.partition(":")
                fields[key.strip()] = val.strip()
        name = fields.get("Package")
        if name and "Filename" in fields:
            # prefer highest version
            if name not in pkgs or fields["Version"] > pkgs[name]["Version"]:
                pkgs[name] = fields
    return pkgs

def main():
    target = sys.argv[1]
    want = sys.argv[2:]
    pkgs = load_index()
    os.makedirs(target, exist_ok=True)
    os.makedirs(BASE / "debs", exist_ok=True)
    ok = fail = 0
    for name in want:
        info = pkgs.get(name)
        if not info:
            print(f"NOT-IN-INDEX: {name}")
            fail += 1
            continue
        fn = info["Filename"]  # pool/.../xxx.deb
        ver = info["Version"]
        out = BASE / "debs" / (fn.rsplit("/", 1)[-1])
        if out.exists() and out.stat().st_size > 1000:
            print(f"CACHED: {name} {ver}")
        else:
            url = "http://deb.debian.org/debian/" + fn
            try:
                urllib.request.urlretrieve(url, out)
                print(f"OK: {name} {ver} -> {out.name} ({out.stat().st_size//1024} KB)")
            except Exception as e:
                print(f"FAIL: {name}: {e}")
                fail += 1
                continue
        subprocess.run(["dpkg-deb", "-x", str(out), target], check=True)
        ok += 1
    print(f"done: ok={ok} fail={fail}")

if __name__ == "__main__":
    main()
