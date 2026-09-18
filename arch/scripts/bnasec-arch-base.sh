#!/bin/bash
# BNAsec-Arch: airootfs package installation (all as plain z via arch_run).
# Spec: Hyprland rice (Catppuccin Mocha), Firefox, Thunar, 6 tools,
#       zram baked in, greetd password login, user bna / host bnasec.
set -e
source /home/z/my-project/arch-build/env.sh

mkdir -p $AIROOTFS/etc/pacman.d/gnupg $AIROOTFS/var/lib/pacman $AIROOTFS/var/cache/pacman/pkg $AIROOTFS/var/log
[ -d $AIROOTFS/etc/pacman.d/gnupg ] || cp -r $ARCH_ROOT/etc/pacman.d/gnupg $AIROOTFS/etc/pacman.d/gnupg

echo "=== syncing airootfs package db ==="
pacman_ai -Sy 2>&1 | tail -2

batch() {
  local name="$1"; shift
  echo "=== BATCH: $name ==="
  pacman_ai -S --noconfirm --needed --overwrite '*' "$@" > "$AB/batch-$name.log" 2>&1
  local rc=$?
  grep -E "error|failed|corrupt" "$AB/batch-$name.log" | head -5
  grep -c "installing " "$AB/batch-$name.log" | awk '{print "  installed "$1" packages"}'
  [ $rc -ne 0 ] && { echo "  BATCH FAILED rc=$rc"; tail -5 "$AB/batch-$name.log"; exit $rc; }
  echo "--- cache cleanup: $(du -sh $PACCACHE 2>/dev/null | cut -f1) before"
  rm -f $PACCACHE/*.pkg.tar.zst*
  df -h / | tail -1 | awk '{print "--- disk free: "$4}'
}

batch base      base linux linux-firmware sudo networkmanager zram-generator \
                e2fsprogs exfatprogs ntfs-3g dosfstools nano git curl openssh \
                zip unzip usbutils pciutils alsa-utils rfkill
batch desktop   hyprland waybar wofi kitty swww dunst fastfetch grim \
                xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
                wl-clipboard brightnessctl
batch fonts     ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji \
                papirus-icon-theme
batch audio     pipewire wireplumber pipewire-pulse
batch shell     zsh zsh-autosuggestions zsh-syntax-highlighting
batch apps      firefox thunar tumbler gvfs
batch tools     aircrack-ng nmap hydra sqlmap
batch login     greetd greetd-tuigreet

echo "=== airootfs size:"
du -sh $AIROOTFS
echo "=== key binaries present:"
for b in usr/bin/hyprland usr/bin/waybar usr/bin/kitty usr/bin/wofi usr/bin/firefox usr/bin/thunar \
         usr/bin/sudo usr/bin/nmap usr/bin/hydra usr/bin/sqlmap usr/bin/dirb usr/bin/aircrack-ng \
         usr/bin/greetd usr/bin/tuigreet usr/bin/swww usr/bin/fastfetch usr/bin/zsh; do
  [ -e "$AIROOTFS/$b" ] && echo "  OK  $b" || echo "  MISSING  $b"
done
echo "=== sudo setuid bit (must be -rwsr-xr-x):"
ls -la $AIROOTFS/usr/bin/sudo | awk '{print "  "$1}'
