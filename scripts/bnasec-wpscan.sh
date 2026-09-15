#!/bin/bash
# Install wpscan gem (pinned 3.8.28) + powerlevel10k into rootfs
set -e
BASE=/home/z/my-project/bnasec-build
. /home/z/my-project/scripts/bnasec-chroot-env.sh

if [ ! -d "$BASE/rootfs/usr/share/powerlevel10k" ]; then
  bnasec_run "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /usr/share/powerlevel10k 2>&1 | tail -2"
fi

if ! bnasec_run "wpscan --version 2>/dev/null" >/dev/null 2>&1; then
  bnasec_run "gem install wpscan -v 3.8.28 --no-document 2>&1 | tail -4"
fi

echo "--- verify ---"
bnasec_run "wpscan --version 2>&1 | head -2"
bnasec_run "ls /usr/share/powerlevel10k/powerlevel10k.zsh-theme"
bnasec_run "aircrack-ng --help 2>&1 | head -1; nmap --version | head -1; hydra -h 2>&1 | head -2 | tail -1; sqlmap --version 2>&1 | head -1; ls /usr/share/dirb/wordlists/ | head -3"
