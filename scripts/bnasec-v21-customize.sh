#!/bin/bash
# BNAsec v2.1.0 rootfs customization:
#   SECURITY: no autologin, password login (bna / bnasec), lock screen
#   WALLPAPERS: 2.jpg default (wave), 3.jpg optional (red moon)
#   STABILITY: zram swap 4G, sysctl tuning, BFQ scheduler, animations off
#   FIREFOX: ESR installed separately via debfetch (already done in tree)
set -e
R=/home/z/my-project/bnasec-build/rootfs

echo "=== 1) SECURITY: remove GDM autologin ==="
cat > $R/etc/gdm3/daemon.conf << 'EOF'
# GDM configuration - BNAsec 2.1.0
# SECURITY: autologin REMOVED in v2.1.0 — password required at login.
[daemon]
AutomaticLoginEnable=false
[security]
[xdmcp]
[chooser]
[debug]
EOF
echo "  gdm3/daemon.conf: autologin disabled"

echo "=== 2) SECURITY: firstboot sets password bnasec (robust) ==="
cat > $R/usr/local/sbin/bnasec-firstboot << 'EOF'
#!/bin/bash
# BNAsec first-boot: create/ensure live user, set credentials, shell, sudo group
set -e
mkdir -p /var/lib/bnasec
if ! id bna >/dev/null 2>&1; then
  useradd -m -u 1000 -s /usr/bin/zsh -c "BNAsec live user" bna 2>/dev/null || \
  useradd -m -s /usr/bin/zsh -c "BNAsec live user" bna
fi
echo 'bna:bnasec' | chpasswd
usermod -s /usr/bin/zsh bna 2>/dev/null || true
usermod -aG sudo bna 2>/dev/null || true
# user must change password at will: hint on desktop + motd
touch /var/lib/bnasec/firstboot-done
EOF
chmod 755 $R/usr/local/sbin/bnasec-firstboot
echo "  firstboot: bna / bnasec + zsh + sudo group"

echo "=== 3) SECURITY: desktop README (skel -> appears in home) ==="
mkdir -p $R/etc/skel/Desktop
cat > $R/etc/skel/Desktop/READ-ME-FIRST.txt << 'EOF'
BNAsec 2.1.0 — READ ME FIRST
============================

LOGIN
  Username: bna
  Password: bnasec
  (Autologin is DISABLED in 2.1.0 for security — you must type this at boot.)

CHANGE YOUR PASSWORD (do this first!)
  Open a terminal and run:  passwd

WALLPAPERS
  Default:  BNAsec Wave   (dark wave, ships as default)
  Optional: BNAsec Red Moon
  Change: Settings -> Appearance -> Background, or right-click desktop.

WHY NO AUTOLOGIN?
  If someone plugs your USB into their machine, they now face a login
  password and cannot read your persistent files.

TOOLS: aircrack-ng, nmap, hydra, wpscan, dirb, sqlmap  + Firefox ESR
PERF: zram swap + tuned sysctl + BFQ scheduler are pre-installed.
EOF
echo "  README on Desktop"

echo "=== 4) WALLPAPERS: glib schema overrides (default = wave) ==="
cat > $R/usr/share/glib-2.0/schemas/15_bnasec.gschema.override << 'EOF'
[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/bnasec/bnasec-wave.jpg'
picture-uri-dark='file:///usr/share/backgrounds/bnasec/bnasec-wave.jpg'
picture-options='zoom'

[org.gnome.desktop.screensaver]
picture-uri='file:///usr/share/backgrounds/bnasec/bnasec-red-moon.jpg'
picture-uri-dark='file:///usr/share/backgrounds/bnasec/bnasec-red-moon.jpg'
lock-enabled=true

[org.gnome.desktop.session]
idle-delay=uint32 300

[org.gnome.desktop.interface]
enable-animations=false
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'
icon-theme='Papirus-Dark'

[org.gnome.shell]
favorite-apps=[ 'firefox-esr.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.TextEditor.desktop' ]
EOF

# Settings -> Background shows both wallpapers with nice names
mkdir -p $R/usr/share/gnome-background-properties
cat > $R/usr/share/gnome-background-properties/bnasec.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<wallpapers>
  <wallpaper deleted="false">
    <name>BNAsec Wave (default)</name>
    <filename>/usr/share/backgrounds/bnasec/bnasec-wave.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#0a0e1a</pcolor>
    <scolor>#0a0e1a</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>BNAsec Red Moon</name>
    <filename>/usr/share/backgrounds/bnasec/bnasec-red-moon.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#1a0a0a</pcolor>
    <scolor>#1a0a0a</scolor>
  </wallpaper>
</wallpapers>
EOF
echo "  overrides + Settings listing done"

echo "=== 5) STABILITY: zram swap (4G zstd, priority 100) ==="
cat > $R/etc/systemd/system/bnasec-zram.service << 'EOF'
[Unit]
Description=BNAsec zram compressed swap (4G zstd)
After=local-fs.target
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/bin/sh -c 'modprobe zram || exit 0; echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null; echo 4G > /sys/block/zram0/disksize; mkswap /dev/zram0; swapon -p 100 /dev/zram0 || true'
ExecStop=/bin/sh -c 'swapoff /dev/zram0 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
mkdir -p $R/etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/bnasec-zram.service $R/etc/systemd/system/multi-user.target.wants/bnasec-zram.service

cat > $R/etc/sysctl.d/99-bnasec-perf.conf << 'EOF'
# BNAsec 2.1.0 stability tuning (3.7GB RAM + zram)
vm.swappiness = 60
vm.vfs_cache_pressure = 50
vm.dirty_background_bytes = 16777216
vm.dirty_bytes = 134217728
kernel.dmesg_restrict = 1
EOF

echo "=== 6) STABILITY: BFQ scheduler for USB/SD storage ==="
cat > $R/etc/modules-load.d/bnasec-bfq.conf << 'EOF'
bfq
EOF
cat > $R/etc/udev/rules.d/60-bnasec-iosched.rules << 'EOF'
# BFQ for rotational/usb block devices (USB live root needs fair queuing)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
EOF
echo "  zram + sysctl + bfq done"

echo "=== 7) default browser = firefox-esr ==="
cat > $R/usr/share/applications/mimeapps.list << 'EOF'
[Default Applications]
text/html=firefox-esr.desktop
x-scheme-handler/http=firefox-esr.desktop
x-scheme-handler/https=firefox-esr.desktop
application/xhtml+xml=firefox-esr.desktop
text/xml=firefox-esr.desktop
application/x-extension-html=firefox-esr.desktop
EOF

echo "=== 8) PLYMOUTH: two-step theme retune for new 1.jpg logo ==="
cat > $R/usr/share/plymouth/themes/bnasec/bnasec.plymouth << 'EOF'
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
VerticalAlignment=.72
WatermarkHorizontalAlignment=.5
WatermarkVerticalAlignment=.38
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

echo "=== 9) compile glib schemas ==="
cd $R && usr/bin/glib-compile-schemas usr/share/glib-2.0/schemas/ 2>&1 | tail -2 || \
  LD_LIBRARY_PATH=$R/usr/lib/x86_64-linux-gnu:$R/lib/x86_64-linux-gnu $R/usr/bin/glib-compile-schemas $R/usr/share/glib-2.0/schemas/ 2>&1 | tail -2

echo "=== 10) update motd ==="
cat > $R/etc/motd << 'EOF'
BNAsec 2.1.0 — secure live pentest platform
login: bna | password: bnasec (CHANGE IT: passwd)
tools: aircrack-ng nmap hydra wpscan dirb sqlmap | browser: firefox-esr
EOF

echo "=== v2.1.0 CUSTOMIZATION DONE ==="
grep -n "AutomaticLogin" $R/etc/gdm3/daemon.conf
ls $R/usr/share/backgrounds/bnasec/
ls $R/etc/systemd/system/multi-user.target.wants/ | grep bnasec
