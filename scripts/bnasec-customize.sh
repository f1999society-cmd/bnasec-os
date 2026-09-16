#!/bin/bash
# BNAsec system customization — writes config into rootfs directly (host file ops).
set -e
BASE=/home/z/my-project/bnasec-build
R=$BASE/rootfs
A=$BASE/assets

############################
# 1) identity
############################
echo "bnasec" > "$R/etc/hostname"
cat > "$R/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	bnasec

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
printf 'BNAsec 2.0.0 \\n \\l\n' > "$R/etc/issue"

############################
# 2) GDM autologin bna
############################
cat > "$R/etc/gdm3/daemon.conf" <<'EOF'
# BNAsec: automatic login as bna
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=bna

[security]

[xdmcp]

[chooser]

[debug]
EOF

############################
# 3) dconf: dark theme, wallpaper, no lock, no sleep, no tracker-indexing noise
############################
mkdir -p "$R/etc/dconf/profile" "$R/etc/dconf/db/local.d"
echo "user-db:user" > "$R/etc/dconf/profile/user"
echo "system-db:local" >> "$R/etc/dconf/profile/user"
cat > "$R/etc/dconf/db/local.d/00-bnasec" <<'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'
enable-hot-corners=false

[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/bnasec-wallpaper.png'
picture-uri-dark='file:///usr/share/backgrounds/bnasec-wallpaper.png'
picture-options='zoom'

[org/gnome/desktop/screensaver]
picture-uri='file:///usr/share/backgrounds/bnasec-wallpaper.png'
lock-enabled=false

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
idle-dim=false

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/privacy]
remember-recent-files=false

[org/gnome/desktop/notifications]
show-in-lock-screen=false
EOF

############################
# 4) zsh + powerlevel10k skeleton
############################
cat > "$R/etc/skel/.zshrc" <<'EOF'
# BNAsec zsh configuration
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" 2>/dev/null
fi
[[ -r /usr/share/powerlevel10k/powerlevel10k.zsh-theme ]] && source /usr/share/powerlevel10k/powerlevel10k.zsh-theme
[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS AUTO_CD INTERACTIVE_COMMENTS
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias llp='ls -alFh --color=auto'
alias ports='ss -tulanp'
EOF
cat > "$R/etc/skel/.p10k.zsh" <<'EOF'
# BNAsec powerlevel10k preset (run `p10k configure` to customize)
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs)
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs virtual_env time)
typeset -g POWERLEVEL9K_DIR_BACKGROUND=236
typeset -g POWERLEVEL9K_DIR_FOREGROUND=51
typeset -g POWERLEVEL9K_VCS_BACKGROUND=234
typeset -g POWERLEVEL9K_VCS_FOREGROUND=76
typeset -g POWERLEVEL9K_STATUS_OK_BACKGROUND=236
typeset -g POWERLEVEL9K_STATUS_ERROR_BACKGROUND=52
typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX=''
typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX='%F{51}>%f '
typeset -g POWERLEVEL9K_TIME_BACKGROUND=236
EOF

############################
# 5) firstboot: set bna:bna + zsh shell
############################
mkdir -p "$R/usr/local/sbin" "$R/etc/systemd/system" "$R/var/lib/bnasec"
cat > "$R/usr/local/sbin/bnasec-firstboot" <<'EOF'
#!/bin/bash
# BNAsec first-boot: set live user credentials + default shell
set -e
mkdir -p /var/lib/bnasec
if id bna >/dev/null 2>&1; then
  echo 'bna:bna' | chpasswd
  usermod -s /usr/bin/zsh bna || true
fi
touch /var/lib/bnasec/firstboot-done
EOF
chmod +x "$R/usr/local/sbin/bnasec-firstboot"
cat > "$R/etc/systemd/system/bnasec-firstboot.service" <<'EOF'
[Unit]
Description=BNAsec first boot configuration
After=live-config.service
ConditionPathExists=!/var/lib/bnasec/firstboot-done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bnasec-firstboot
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sf ../bnasec-firstboot.service "$R/etc/systemd/system/multi-user.target.wants/bnasec-firstboot.service"

############################
# 6) persistence auto-provision (whole-root overlay, all free space)
############################
cat > "$R/usr/local/sbin/bnasec-persist-setup" <<'EOF'
#!/bin/bash
# BNAsec: auto-create a full-root persistence partition on the boot USB
# using ALL remaining free space (>=2GiB), then reboot once to activate it.
LOG=/run/bnasec-persist-setup.log
exec > >(tee "$LOG") 2>&1
msg() { echo "[bnasec-persist] $*"; plymouth display-message --text="$*" 2>/dev/null || true; }

if findmnt -n /run/live/persistence >/dev/null 2>&1; then
  msg "persistence already active"
  exit 0
fi

src=$(findmnt -nro SOURCE /run/live/medium 2>/dev/null) || { msg "no boot medium found"; exit 0; }
case "$src" in
  /dev/sr*|/dev/loop*) msg "optical/loop medium, skipping persistence setup"; exit 0 ;;
esac
dev=$(lsblk -nro PKNAME "$src" 2>/dev/null | head -1)
[ -n "$dev" ] || { msg "cannot resolve boot device"; exit 0; }
disk="/dev/$dev"

if [ -f "/sys/class/block/$dev/removable" ] && [ "$(cat "/sys/class/block/$dev/removable")" != "1" ]; then
  msg "$disk is not removable, skipping persistence setup"
  exit 0
fi

total=$(blockdev --getsize64 "$disk") || exit 0
lastend=$(lsblk -bno END "$disk" 2>/dev/null | sort -n | tail -1); lastend=${lastend:-0}
gap=$(( total - lastend ))
if [ "$gap" -lt $((2*1024*1024*1024)) ]; then
  msg "only $((gap/1024/1024))MiB free on $disk — need >=2GiB, skipping"
  exit 0
fi

msg "creating $((gap/1024/1024/1024))GiB persistence partition on $disk ..."
sgdisk -e "$disk" >/dev/null 2>&1 || true
if ! sgdisk -N 2 "$disk" >/dev/null 2>&1; then
  msg "partition creation failed — continuing without persistence"
  exit 0
fi
sgdisk -t 2:8300 "$disk" >/dev/null 2>&1 || true
sgdisk -c 2:"persistence" "$disk" >/dev/null 2>&1 || true
partx -a "$disk" 2>/dev/null || true
udevadm settle 2>/dev/null || true

p2=""
for cand in "$disk"2 "/dev/${dev}p2"; do
  [ -b "$cand" ] && p2="$cand" && break
done
if [ -z "$p2" ]; then
  msg "partition node missing — continuing without persistence"
  exit 0
fi

mkfs.ext4 -L persistence -q -F "$p2" || { msg "mkfs.ext4 failed"; exit 0; }
sync
msg "persistence ready — rebooting to activate ..."
sleep 3
systemctl reboot --no-wall 2>/dev/null || reboot -f
EOF
chmod +x "$R/usr/local/sbin/bnasec-persist-setup"
cat > "$R/etc/systemd/system/bnasec-persist.service" <<'EOF'
[Unit]
Description=BNAsec full-root persistence provisioning
After=basic.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bnasec-persist-setup
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
ln -sf ../bnasec-persist.service "$R/etc/systemd/system/multi-user.target.wants/bnasec-persist.service"

############################
# 7) persistence self-test (inert without bnasec.persisttest kernel arg)
############################
cat > "$R/usr/local/sbin/bnasec-persisttest" <<'EOF'
#!/bin/bash
exec >>/dev/console 2>&1
echo "[bnasec-persisttest] === persistence self-test ==="
echo "[bnasec-persisttest] overlays:"; findmnt -n -t overlay 2>/dev/null | sed 's/^/  /' || echo "  none"
if [ -f /var/lib/bnasec/persist-marker ]; then
  echo "[bnasec-persisttest] PRE-EXISTING MARKER: $(cat /var/lib/bnasec/persist-marker)  <- WHOLE-ROOT PERSISTENCE CONFIRMED"
else
  echo "[bnasec-persisttest] no pre-existing marker (fresh or non-persistent boot)"
fi
mkdir -p /var/lib/bnasec
date +%s > /var/lib/bnasec/persist-marker
echo "[bnasec-persisttest] marker now: $(cat /var/lib/bnasec/persist-marker)"
echo "[bnasec-persisttest] === done ==="
EOF
chmod +x "$R/usr/local/sbin/bnasec-persisttest"
cat > "$R/etc/systemd/system/bnasec-persisttest.service" <<'EOF'
[Unit]
Description=BNAsec persistence self-test
ConditionKernelCommandLine=bnasec.persisttest
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bnasec-persisttest
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
ln -sf ../bnasec-persisttest.service "$R/etc/systemd/system/multi-user.target.wants/bnasec-persisttest.service"

############################
# 8) masks: tracker miners (user units) + sleep/suspend
############################
mkdir -p "$R/etc/systemd/user"
for u in "$R"/usr/lib/systemd/user/tracker-*.service; do
  [ -e "$u" ] || continue
  ln -sf /dev/null "$R/etc/systemd/user/$(basename "$u")"
done
for t in suspend.target sleep.target hibernate.target hybrid-sleep.target; do
  ln -sf /dev/null "$R/etc/systemd/system/$t"
done
# belt & braces: hide tracker autostart entries from GNOME session
mkdir -p "$R/etc/xdg/autostart"
for d in "$R"/usr/share/xdg/autostart/tracker-*.desktop; do
  [ -e "$d" ] || continue
  printf '[Unit]\nHidden=true\n' > "$R/etc/xdg/autostart/$(basename "$d")"
done

############################
# 9) plymouth bnasec splash theme
############################
SPINNER="$R/usr/share/plymouth/themes/spinner"
BNASEC_T="$R/usr/share/plymouth/themes/bnasec"
mkdir -p "$BNASEC_T" "$R/usr/share/backgrounds"
cp "$SPINNER"/*.png "$BNASEC_T/" 2>/dev/null || true
cp "$A/bnasec-logo.png" "$BNASEC_T/bnasec-logo.png"
cp "$A/bnasec-logo.png" "$BNASEC_T/watermark.png"
cat > "$BNASEC_T/bnasec.plymouth" <<'EOF'
[Plymouth Theme]
Name=BNAsec
Description=BNAsec boot splash
ModuleName=two-step

[two-step]
Font=DejaVu Sans 14
TitleFont=DejaVu Sans Bold 30
ImageDir=/usr/share/plymouth/themes/bnasec
DialogHorizontalAlignment=.5
DialogVerticalAlignment=.7
TitleHorizontalAlignment=.5
TitleVerticalAlignment=.382
HorizontalAlignment=.5
VerticalAlignment=.7
WatermarkHorizontalAlignment=.5
WatermarkVerticalAlignment=.4
WatermarkFilename=bnasec-logo.png
Transition=none
TransitionDuration=0.0
BackgroundStartColor=0x0a0e1a
BackgroundEndColor=0x0a0e1a
MessageBelowAnimation=true

[boot-up]
UseEndAnimation=false

[shutdown]
UseEndAnimation=false

[reboot]
UseEndAnimation=false
EOF
cat > "$R/usr/share/plymouth/plymouthd.defaults" <<'EOF'
# BNAsec default splash
[Daemon]
Theme=bnasec
ShowDelay=0
DeviceTimeout=5
EOF
rm -f "$R/usr/share/plymouth/themes/default.plymouth"
ln -sf bnasec/bnasec.plymouth "$R/usr/share/plymouth/themes/default.plymouth"

############################
# 10) wallpaper + future-installs trim hardening
############################
cp "$A/bnasec-wallpaper.png" "$R/usr/share/backgrounds/bnasec-wallpaper.png"
printf 'path-exclude=/usr/share/help/*\n' >> "$R/etc/dpkg/dpkg.cfg.d/01-bnasec-trim"

############################
# 11) in-chroot: dconf db compile
############################
. /home/z/my-project/scripts/bnasec-chroot-env.sh
bnasec_run "dconf update"
bnasec_run "ls /etc/dconf/db/local; plymouth-set-default-theme 2>/dev/null || cat /usr/share/plymouth/plymouthd.defaults | grep Theme"

echo "--- customize done ---"
ls "$BNASEC_T" | head -5
