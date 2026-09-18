#!/bin/bash
# BNAsec-Arch: fixups after first config pass
set -e
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS

echo "=== F1) wheel group: append bna (any gid) ==="
sed -i 's/^wheel:x:[0-9]*:$/&,bna/' $R/etc/group
grep '^wheel:' $R/etc/group

echo "=== F2) locale en_US.UTF-8 via I18NPATH ==="
mkdir -p $R/usr/lib/locale
env BNASEC_FAKE_ROOT=1 BNASEC_FAKE_CHOWN=1 LD_PRELOAD="$TOOLS/symlink-shim.so" I18NPATH="$R/usr/share/i18n" \
  "$R/lib64/ld-linux-x86-64.so.2" --library-path "$R/usr/lib:$R/usr/lib/systemd:$R/lib" \
  "$R/usr/bin/localedef" --prefix $R -c -f UTF-8 -i en_US en_US.UTF-8 2>&1 | tail -1 || true
ls -la $R/usr/lib/locale/locale-archive 2>/dev/null && echo "  locale-archive OK"

echo "=== F3) lxqt-policykit (manual extract; pacman chroot EPERM avoided) ==="
pacman_ai -Sw --noconfirm lxqt-policykit > /dev/null 2>&1 || true
PKG=$(ls $PACCACHE/lxqt-policykit-*.pkg.tar.zst 2>/dev/null | head -1)
if [ -n "$PKG" ]; then
  tar -xzf "$PKG" -C $R .PKGINFO 2>/dev/null && grep -q depend $R/.PKGINFO 2>/dev/null || true
  # pull its deps list from .PKGINFO and install them via pacman (they lack scriptlets)
  DEPS=$(grep '^depend = ' $R/.PKGINFO 2>/dev/null | cut -d= -f3- | sed 's/>.*//; s/<.*//; s/=.*//' | tr '\n' ' ')
  rm -f $R/.PKGINFO
  echo "  deps: $DEPS"
  [ -n "$(echo $DEPS | tr -d ' ')" ] && pacman_ai -S --noconfirm --needed $DEPS > /dev/null 2>&1 && echo "  deps installed"
  tar -xzf "$PKG" -C $R usr/ && echo "  extracted $(basename $PKG)"
  rm -f $R/.PKGINFO $R/.MTREE $R/.INSTALL
  ls $R/usr/bin/ | grep -i policykit || ls $R/usr/lib/*/lxqt* 2>/dev/null | head -2
else
  echo "  download failed; will rely on fallback agent"
fi

echo "=== F4) Catppuccin Mocha GTK theme (mauve accent) ==="
rm -rf /tmp/cc && mkdir -p /tmp/cc
if [ ! -d $R/usr/share/themes/Catppuccin-Mocha ]; then
  # v1.0.3 assets use lowercase names; install under the name rice.sh expects
  for u in "https://github.com/catppuccin/gtk/releases/download/v1.0.3/catppuccin-mocha-mauve-standard%2Bdefault.zip" \
           "https://github.com/catppuccin/gtk/releases/download/v1.0.2/catppuccin-mocha-mauve-standard%2Bdefault.zip"; do
    curl -fsSL -o /tmp/cc/t.zip "$u" 2>/dev/null && break
  done
  if [ -s /tmp/cc/t.zip ]; then
    cd /tmp/cc && unzip -oq t.zip
    D=$(ls -d catppuccin-mocha-mauve-standard+default 2>/dev/null || ls -d catppuccin-mocha*standard* 2>/dev/null | grep -v hdpi | grep -v xhdpi | head -1)
    [ -n "$D" ] && cp -a "$D" $R/usr/share/themes/Catppuccin-Mocha && echo "  installed as Catppuccin-Mocha (from $D)"
  else
    echo "  theme download failed — will use Adwaita-dark fallback"
  fi
fi
ls $R/usr/share/themes/

echo "=== F5) verify sudo setuid survived pacman ==="
ls -la $R/usr/bin/sudo | awk '{print "  "$1, $NF}'
echo "=== FIXUPS DONE ==="
