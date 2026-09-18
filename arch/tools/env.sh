#!/bin/bash
# BNAsec-Arch build environment v2 — all execution as plain user z.
#
# Architecture (empirically proven in this sandbox):
#   - sandbox kills symlink(2) AND symlinkat(2) from uid-0 contexts
#     (incl. user-namespace root); symlinkat from plain user z is allowed
#   - therefore: NO proot/chroot/userns. Everything runs as z with:
#       * LD_PRELOAD symlink-shim.so  (symlink->symlinkat, fake uid, fake chown)
#       * Arch binaries run under Arch's own ld.so + libraries (no glibc skew)
#   - pacman -r installs into the target tree; hooks neutralized via config
#   - post-install config via native --root/--prefix/-b options + manual files
export AB=/home/z/my-project/arch-build
export TOOLS=$AB/tools
export PATH="$TOOLS/zstd-root/usr/bin:$TOOLS/proot-root/usr/bin:$PATH"
export LD_LIBRARY_PATH="$TOOLS/proot-root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

export ARCH_ROOT=$AB/arch-root
export GCONV_PATH=$ARCH_ROOT/usr/lib/gconv   # mtools codepage conversion
export AIROOTFS=$AB/airootfs
export PACCONF=$AB/pacman.conf
export PACCACHE=$AB/paccache

# Run an Arch binary as z under the Arch runtime with the shim.
# Usage: arch_run2 <ROOT> <path-under-ROOT> [args...]
#   Uses ROOT's own loader+libs (LD_LIBRARY_PATH wins over DT_RUNPATH, which
#   is required for libsystemd-shared in /usr/lib/systemd).
arch_ld() { echo "$1/lib64/ld-linux-x86-64.so.2"; }
arch_run2() {
  local ROOT="$1"; shift
  env BNASEC_FAKE_ROOT=1 BNASEC_FAKE_CHOWN=1 LD_PRELOAD="$TOOLS/symlink-shim.so" \
      "$(arch_ld "$ROOT")" --library-path "$ROOT/usr/lib:$ROOT/usr/lib/systemd:$ROOT/lib" "$ROOT/$1" "${@:2}" 2>"$AB/last-arch-run.err"
  local rc=$?
  [ $rc -ne 0 ] && [ -s "$AB/last-arch-run.err" ] && head -3 "$AB/last-arch-run.err" >&2
  return $rc
}
arch_run() { arch_run2 "$ARCH_ROOT" "$@"; }
# quick variants — explicit per-root paths (pacman 7.1 needs CLI overrides)
pm() {  # pm <ROOT> <pacman args...>
  local R="$1"; shift
  arch_run2 "$R" usr/bin/pacman -r "$R" --config "$PACCONF" \
    --dbpath "$R/var/lib/pacman" --cachedir "$PACCACHE" \
    --gpgdir "$R/etc/pacman.d/gnupg" --hookdir "$AB/empty-hooks" \
    --logfile "$AB/pacman-$(basename $R).log" "$@"
}
pacman_b()  { pm "$ARCH_ROOT" "$@"; }
pacman_ai() { pm "$AIROOTFS" "$@"; }
mkarch()    { arch_run "" usr/bin/mkarchroot "$@" 2>/dev/null || true; }

export LD_PRELOAD="$TOOLS/symlink-shim.so"   # for plain-host commands too
