#!/bin/bash
# Stage B: trim config + install full GNOME + security toolchain into rootfs
# usage: bash bnasec-stageB.sh [download|install|repair]
set -e
BASE=/home/z/my-project/bnasec-build
. /home/z/my-project/scripts/bnasec-chroot-env.sh

PKGS="gnome-core gdm3 network-manager network-manager-gnome xdg-user-dirs xdg-desktop-portal-gnome locales user-setup zsh git curl ca-certificates sudo live-boot live-config live-config-systemd linux-image-amd64 initramfs-tools busybox-static firmware-linux firmware-linux-nonfree firmware-misc-nonfree firmware-iwlwifi firmware-realtek firmware-atheros firmware-brcm80211 firmware-libertas wireless-regdb iw aircrack-ng nmap hydra dirb sqlmap ruby-full ruby-dev build-essential libcurl4-openssl-dev libxml2-dev libxslt1-dev zlib1g-dev pkg-config nano less pciutils usbutils file bash-completion gdisk plymouth plymouth-themes plymouth-label"

case "${1:-download}" in
download)
  bnasec_run "printf 'path-exclude=/usr/share/doc/*\npath-include=/usr/share/doc/*/copyright\npath-exclude=/usr/share/man/*\npath-exclude=/usr/share/locale/*\npath-include=/usr/share/locale/en*\npath-include=/usr/share/locale/locale.alias\npath-exclude=/usr/share/info/*\n' > /etc/dpkg/dpkg.cfg.d/01-bnasec-trim"
  bnasec_run "apt-get update"
  bnasec_run "apt-get -y --download-only install $PKGS"
  echo "--- stage B download done ---"
  ;;
install)
  bnasec_run "DEBIAN_FRONTEND=noninteractive apt-get -y install $PKGS"
  echo "--- stage B install done ---"
  ;;
repair)
  bnasec_run "DEBIAN_FRONTEND=noninteractive dpkg --configure -a" || true
  bnasec_run "DEBIAN_FRONTEND=noninteractive apt-get -f install -y" || true
  bnasec_run "DEBIAN_FRONTEND=noninteractive dpkg --configure -a" || true
  echo "--- remaining unconfigured (should be empty): ---"
  bnasec_run "dpkg -l 2>/dev/null | grep -E '^i[FU]' || true"
  bnasec_run "apt-get clean; rm -rf /var/lib/apt/lists/*"
  echo "--- stage B repair done ---"
  du -sh "$BASE/rootfs"
  ;;
esac
