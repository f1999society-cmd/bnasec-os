#!/bin/bash
# BNAsec-Arch: system configuration baked into airootfs.
# Identity: host bnasec, user bna (password bnasec — user changes later).
# Secure: greetd + tuigreet password login, NO autologin.
set -e
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS

w() { # write file with dirs:  w <path> [mode]
  local p="$R/$1"; shift
  mkdir -p "$(dirname "$p")"
  cat > "$p"
  if [ -n "$1" ]; then chmod "$1" "$p"; fi
  return 0
}

echo "=== 1) identity ==="
echo bnasec > $R/etc/hostname
w etc/hosts <<'EOF'
127.0.0.1 localhost
::1       localhost
127.0.1.1 bnasec.localdomain bnasec
EOF
w etc/locale.conf <<'EOF'
LANG=en_US.UTF-8
EOF
w etc/vconsole.conf <<'EOF'
KEYMAP=us
FONT=latarcyrheb-sun16
EOF
# machine-id (fixed so journald is stable across boots of the same live media)
[ -s $R/etc/machine-id ] || (openssl rand -hex 16 | tr -d '\n' > $R/etc/machine-id; echo >> $R/etc/machine-id)

echo "=== 2) apply package sysusers + tmpfiles ==="
arch_run2 $R usr/bin/systemd-sysusers --root $R 2>&1 | tail -2 || true
arch_run2 $R usr/bin/systemd-tmpfiles --root $R --create 2>&1 | grep -vE "line|Warning" | tail -2 || true

echo "=== 3) user bna + wheel + sudo ==="
HASH=$(openssl passwd -6 'bnasec')
grep -q '^bna:' $R/etc/passwd || echo "bna:x:1000:1000:BNAsec User:/home/bna:/bin/zsh" >> $R/etc/passwd
grep -q '^bna:' $R/etc/group  || echo "bna:x:1000:" >> $R/etc/group
grep -q '^bna:' $R/etc/shadow || echo "bna:$HASH:19700:0:99999:7:::" >> $R/etc/shadow
# wheel membership (wheel gid 10 on Arch)
sed -i 's/^wheel:x:10:$/wheel:x:10:bna/; s/^wheel:x:10:root$/wheel:x:10:root,bna/' $R/etc/group
grep '^wheel:' $R/etc/group
w etc/sudoers.d/10-bnasec-wheel 440 <<'EOF'
%wheel ALL=(ALL:ALL) ALL
Defaults env_reset, mail_badpass
EOF
chmod 440 $R/etc/sudoers.d/10-bnasec-wheel

# pam_shells: zsh package adds itself via scriptlet (never runs rootless) — append manually
grep -q '/bin/zsh' $R/etc/shells || printf '/bin/zsh\n/usr/bin/zsh\n' >> $R/etc/shells
# root rescue password (same as bna — user changes both later)
ROOTHASH=$(openssl passwd -6 'bnasec')
sed -i "s|^root:\\*:|root:$ROOTHASH:|" $R/etc/shadow

echo "=== 4) greetd + tuigreet (password login, no autologin) ==="
w etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --asterisks --remember --cmd Hyprland"
user = "greeter"
EOF
mkdir -p $R/etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/greetd.service $R/etc/systemd/system/multi-user.target.wants/greetd.service
ls -la $R/etc/systemd/system/multi-user.target.wants/ | tail -2

echo "=== 5) services: NetworkManager ==="
ln -sf /usr/lib/systemd/system/NetworkManager.service $R/etc/systemd/system/multi-user.target.wants/NetworkManager.service
ln -sf /usr/lib/systemd/system/systemd-resolved.service $R/etc/systemd/system/multi-user.target.wants/systemd-resolved.service 2>/dev/null || true
# resolv.conf managed by NetworkManager
rm -f $R/etc/resolv.conf
ln -sf /run/NetworkManager/resolv.conf $R/etc/resolv.conf

echo "=== 6) zram swap (baked-in anti-freeze) ==="
w etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram, 4096)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF
# zram-generator is auto-triggered by the systemd generator; make sure the
# device unit deps exist at boot: nothing else needed.

echo "=== 7) sysctl perf tuning ==="
w etc/sysctl.d/99-bnasec-perf.conf <<'EOF'
vm.swappiness = 20
vm.vfs_cache_pressure = 50
vm.dirty_background_bytes = 16777216
vm.dirty_bytes = 134217728
kernel.unprivileged_userns_clone = 1
EOF

echo "=== 8) BFQ scheduler for removable/media devices ==="
w etc/modules-load.d/bnasec-bfq.conf <<'EOF'
bfq
EOF
w etc/udev/rules.d/60-bnasec-iosched.rules <<'EOF'
# BFQ for block devices (USB sticks, SD, HDD/SSD) — smoother under load
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="*", ATTR{queue/scheduler}="bfq"
EOF

echo "=== 9) polkit: wheel can power off / reboot without prompt ==="
w etc/polkit-1/rules.d/50-bnasec.rules <<'EOF'
polkit.addRule(function(action, subject) {
  var ok = ["org.freedesktop.login1.power-off",
            "org.freedesktop.login1.power-off-multiple-sessions",
            "org.freedesktop.login1.reboot",
            "org.freedesktop.login1.reboot-multiple-sessions",
            "org.freedesktop.login1.suspend",
            "org.freedesktop.login1.hibernate"];
  if (ok.indexOf(action.id) >= 0 && subject.isInGroup("wheel")) {
    return polkit.Result.YES;
  }
});
EOF

echo "=== 10) environment ==="
w etc/environment <<'EOF'
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland;xcb
EDITOR=nano
VISUAL=nano
BNASEC_OS=1
EOF

echo "=== 11) locales: generate en_US.UTF-8 into airootfs archive ==="
mkdir -p $R/usr/lib/locale
arch_run2 $R usr/bin/localedef --prefix $R --input-path $R/usr/share/i18n/locales \
  -i en_US -c -f UTF-8 en_US.UTF-8 2>&1 | grep -vE "^$" | tail -2 || true
ls -la $R/usr/lib/locale/ 2>/dev/null | head -3

echo "=== 12) firefox policies (privacy + no update popups on live media) ==="
w usr/lib/firefox/distribution/policies.json <<'EOF'
{
  "policies": {
    "DisableAppUpdate": true,
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "NoDefaultBrowserChecking": true,
    "SkipTermsOfUse": true,
    "DontCheckDefaultBrowser": true,
    "Preferences": {
      "browser.startup.page": { "Value": 0, "Status": "locked" },
      "browser.warnOnQuit": { "Value": false, "Status": "locked" },
      "datareporting.policy.dataSubmissionPolicyAcceptedVersion": { "Value": 2, "Status": "locked" }
    }
  }
}
EOF

echo "=== 13) powerlevel10k theme ==="
if [ ! -d $R/usr/share/zsh-theme-powerlevel10k ]; then
  git clone --depth=1 --quiet https://github.com/romkatv/powerlevel10k.git $R/usr/share/zsh-theme-powerlevel10k 2>&1 | tail -1
fi
ls $R/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme >/dev/null && echo "  p10k OK"

echo "=== 14) catppuccin gtk theme ==="
mkdir -p $R/usr/share/themes /tmp/catppuccin
if [ ! -d $R/usr/share/themes/Catppuccin-Mocha-Standard-+Default-Dark ]; then
  curl -fsSL -o /tmp/catppuccin/theme.zip "https://github.com/catppuccin/gtk/releases/download/v1.0.3/catppuccin-mocha-standard-default-dark.zip" 2>/dev/null \
    || curl -fsSL -o /tmp/catppuccin/theme.zip "https://github.com/catppuccin/gtk/releases/download/v1.0.2/catppuccin-mocha-standard-default-dark.zip" 2>/dev/null || true
  if [ -s /tmp/catppuccin/theme.zip ]; then
    cd /tmp/catppuccin && unzip -oq theme.zip && ls -d */ | head -3
    for d in /tmp/catppuccin/Catppuccin-Mocha-Standard-+Default-Dark*; do
      [ -d "$d" ] && cp -a "$d" $R/usr/share/themes/
    done
  else
    echo "  theme download failed — will use Adwaita-dark fallback"
  fi
fi
ls $R/usr/share/themes/ | head -5

echo "=== 15) polkit auth agent (small, autostarted by Hyprland config) ==="
pacman_ai -S --noconfirm --needed lxqt-policykit 2>&1 | tail -1
rm -f $PACCACHE/*.pkg.tar.zst*

echo "=== CONFIG COMPLETE ==="
df -h / | tail -1
