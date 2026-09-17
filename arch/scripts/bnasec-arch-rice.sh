#!/bin/bash
# BNAsec-Arch rice part 1: Hyprland + Waybar + Kitty + Wofi + Dunst + GTK + zsh
# Catppuccin Mocha palette:
#   base #1e1e2e  mantle #181825  crust #11111b  surface0 #313244
#   text #cdd6f4  subtext0 #a6adc8  overlay0 #6c7086
#   mauve #cba6f7  pink #f5c2e7  lavender #b4befe  blue #89b4fa  sapphire #74c7ec
#   red #f38ba8  peach #fab387  yellow #f9e2af  green #a6e3a1  teal #94e2d5
set -e
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS
w() { local p="$R/$1"; shift; mkdir -p "$(dirname "$p")"; cat > "$p"; if [ -n "$1" ]; then chmod "$1" "$p"; fi; return 0; }

echo "=== hyprland.conf ==="
w etc/skel/.config/hypr/hyprland.conf <<'EOF'
# ============================================================
#  BNAsec Arch — Hyprland rice (Catppuccin Mocha)
# ============================================================

monitor=,preferred,auto,1

env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland
env = QT_QPA_PLATFORM,wayland;xcb
env = MOZ_ENABLE_WAYLAND,1
env = GDK_BACKEND,wayland,x11

# --- input ---
input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
    touchpad {
        natural_scroll = true
        tap-to-click = true
    }
}

gestures {
    workspace_swipe = true
    workspace_swipe_fingers = 3
}

# --- general look ---
general {
    gaps_in = 6
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(cba6f7ee) rgba(f5c2e7ee) rgba(b4befe) 45deg
    col.inactive_border = rgba(313244aa)
    layout = dwindle
    resize_on_border = true
}

decoration {
    rounding = 10
    blur {
        enabled = true
        size = 6
        passes = 3
        new_optimizations = true
        vibrancy = 0.1696
        contrast = 1.1
    }
    shadow {
        enabled = true
        range = 12
        render_power = 3
        color = rgba(11111b88)
    }
}

animations {
    enabled = true
    bezier = overshoot, 0.13, 0.99, 0.29, 1.1
    bezier = smoothOut, 0.36, 0, 0.66, -0.56
    bezier = smoothIn, 0.25, 1, 0.5, 1
    animation = windows, 1, 4, overshoot, slide
    animation = windowsOut, 1, 3.2, smoothOut
    animation = windowsMove, 1, 4, overshoot
    animation = border, 1, 6, default
    animation = borderangle, 1, 60, loop, once
    animation = fade, 1, 3, smoothIn
    animation = fadeDim, 1, 3, smoothIn
    animation = workspaces, 1, 4, overshoot, slide
    animation = layers, 1, 4, overshoot, slide
    animation = specialWorkspace, 1, 4, overshoot, slidevert
}

dwindle {
    pseudotile = true
    preserve_split = true
}

misc {
    force_default_wallpaper = 0
    disable_hyprland_logo = true
    disable_splash_rendering = true
    vfr = true
    new_window_takes_over_fullscreen = 2
}

# --- autostart ---
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = swww-daemon --format xrgb
exec-once = sleep 1 && bnasec-wallpaper
exec-once = waybar
exec-once = dunst
exec-once = lxqt-policykit-agent
exec-once = wl-paste --type text --watch cliphist store

# --- keybinds ---
$mod = SUPER
$terminal = kitty
$menu = wofi --show drun

bind = $mod, Return, exec, $terminal
bind = $mod, D, exec, $menu
bind = $mod, E, exec, thunar
bind = $mod, B, exec, firefox
bind = $mod SHIFT, F, exec, firefox --private-window
bind = $mod, Q, killactive
bind = $mod, M, exit
bind = $mod, V, togglefloating
bind = $mod, F, fullscreen
bind = $mod, P, pseudo
bind = $mod, J, togglesplit
bind = $mod, left, movefocus, l
bind = $mod, right, movefocus, r
bind = $mod, up, movefocus, u
bind = $mod, down, movefocus, d
bind = $mod SHIFT, left, movewindow, l
bind = $mod SHIFT, right, movewindow, r
bind = $mod SHIFT, up, movewindow, u
bind = $mod SHIFT, down, movewindow, d
bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod, 6, workspace, 6
bind = $mod, 7, workspace, 7
bind = $mod, 8, workspace, 8
bind = $mod, 9, workspace, 9
bind = $mod, 0, workspace, 10
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5
bind = $mod SHIFT, 6, movetoworkspace, 6
bind = $mod SHIFT, 7, movetoworkspace, 7
bind = $mod SHIFT, 8, movetoworkspace, 8
bind = $mod SHIFT, 9, movetoworkspace, 9
bind = $mod SHIFT, 0, movetoworkspace, 10
bind = $mod, mouse_down, workspace, e+1
bind = $mod, mouse_up, workspace, e-1

# media / volume / brightness
bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindl  = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bindel = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

# screenshots (grim is baked in)
bind = , Print, exec, grim "$HOME/Pictures/Screenshots/bnasec-$(date +%Y%m%d-%H%M%S).png"

# mouse resize
bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow

# --- window rules ---
windowrule = float, ^(pavucontrol)$
windowrule = float, ^(nm-connection-editor)$
windowrule = float, ^(blueman-manager)$
windowrule = float, title:^(Picture-in-Picture)$
windowrule = pin, title:^(Picture-in-Picture)$
EOF

echo "=== waybar config + css ==="
w etc/skel/.config/waybar/config.jsonc <<'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 34,
    "margin-top": 8,
    "margin-left": 10,
    "margin-right": 10,
    "modules-left": ["hyprland/workspaces", "hyprland/window"],
    "modules-center": ["clock"],
    "modules-right": ["tray", "network", "cpu", "memory", "battery", "pulseaudio"],
    "hyprland/workspaces": {
        "format": "{name}",
        "on-click": "activate",
        "format-icons": { "active": "" }
    },
    "hyprland/window": { "max-length": 42, "separate-outputs": true },
    "clock": {
        "format": "  {:%H:%M  %a %d %b}",
        "tooltip-format": "<tt><small>{calendar}</small></tt>"
    },
    "network": {
        "format-wifi": " {essid}",
        "format-ethernet": "  wired",
        "format-disconnected": "  offline",
        "tooltip-format": "{ifname}: {ipaddr}/{cidr}",
        "max-length": 30
    },
    "cpu": { "format": " {usage}%", "interval": 3 },
    "memory": { "format": " {percentage}%", "interval": 3 },
    "battery": {
        "states": { "warning": 25, "critical": 10 },
        "format": "{icon} {capacity}%",
        "format-icons": ["", "", "", "", ""]
    },
    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": "  muted",
        "format-icons": { "default": ["", ""] }
    },
    "tray": { "icon-size": 16, "spacing": 8 }
}
EOF

w etc/skel/.config/waybar/style.css <<'EOF'
/* BNAsec Arch — Waybar, Catppuccin Mocha */
* { font-family: "JetBrainsMono Nerd Font", sans-serif; font-size: 12px;
    font-weight: 600; min-height: 0; }

window#waybar {
    background: rgba(30, 30, 46, 0.85);
    color: #cdd6f4;
    border: 1px solid rgba(203, 166, 247, 0.35);
    border-radius: 14px;
}

#workspaces button {
    padding: 0 7px;
    margin: 4px 2px;
    color: #a6adc8;
    background: transparent;
    border-radius: 10px;
    transition: all 0.25s ease;
}
#workspaces button.active {
    color: #1e1e2e;
    background: #cba6f7;
}
#workspaces button:hover { color: #b4befe; background: rgba(49, 50, 68, 0.6); }

#window { color: #cdd6f4; font-weight: 500; padding: 0 10px; }

#clock { color: #b4befe; padding: 0 12px; }
#network { color: #94e2d5; padding: 0 8px; }
#network.disconnected { color: #f38ba8; }
#cpu { color: #fab387; padding: 0 8px; }
#memory { color: #f9e2af; padding: 0 8px; }
#battery { color: #a6e3a1; padding: 0 8px; }
#battery.warning:not(.charging) { color: #fab387; }
#battery.critical:not(.charging) { color: #f38ba8; }
#pulseaudio { color: #cba6f7; padding: 0 8px; }
#pulseaudio.muted { color: #6c7086; }
#tray { padding: 0 8px; }
EOF

echo "=== kitty ==="
w etc/skel/.config/kitty/kitty.conf <<'EOF'
# BNAsec Arch — kitty, Catppuccin Mocha
font_family      family="JetBrainsMono Nerd Font"
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        11.0

window_padding_width 10
background_opacity 0.92
confirm_os_window_close 0
enable_audio_bell no
scrollback_lines 8192
cursor_shape beam
url_style curly
EOF

w etc/skel/.config/kitty/themes/bnasec-mocha.conf <<'EOF'
# Catppuccin Mocha
foreground            #cdd6f4
background            #1e1e2e
selection_foreground  #1e1e2e
selection_background  #f5c2e7
cursor                #f5c2e7
cursor_text_color     #1e1e2e
url_color             #89b4fa
active_border_color   #cba6f7
inactive_border_color #6c7086
bell_border_color     #f9e2af
active_tab_foreground   #11111b
active_tab_background   #cba6f7
inactive_tab_foreground #cdd6f4
inactive_tab_background #181825
tab_bar_background    #11111b
mark1_foreground #1e1e2e
mark1_background #b4befe
color0  #45475a
color8  #585b70
color1  #f38ba8
color9  #f38ba8
color2  #a6e3a1
color10 #a6e3a1
color3  #f9e2af
color11 #f9e2af
color4  #89b4fa
color12 #89b4fa
color5  #f5c2e7
color13 #f5c2e7
color6  #94e2d5
color14 #94e2d5
color7  #bac2de
color15 #a6adc8
EOF
# link theme into kitty.conf include
cat >> $R/etc/skel/.config/kitty/kitty.conf <<'EOF'
include themes/bnasec-mocha.conf
EOF

echo "=== wofi ==="
w etc/skel/.config/wofi/config <<'EOF'
width=620
height=420
show=drun
matching=fuzzy
insensitive=true
hide_scroll=true
allow_images=true
image_size=26
term=kitty
prompt=launch
EOF

w etc/skel/.config/wofi/style.css <<'EOF'
/* BNAsec Arch — wofi, Catppuccin Mocha */
* { font-family: "JetBrainsMono Nerd Font", monospace; font-size: 13px; }

window {
    background-color: rgba(24, 24, 37, 0.92);
    border: 2px solid rgba(203, 166, 247, 0.5);
    border-radius: 14px;
}
#input {
    margin: 12px;
    padding: 10px;
    background-color: rgba(49, 50, 68, 0.7);
    color: #cdd6f4;
    border: none;
    border-radius: 10px;
}
#inner-box { margin: 6px; background: transparent; }
#outer-box  { margin: 4px; background: transparent; }
#scroll { margin: 2px; }
#text { margin: 5px 8px; color: #cdd6f4; }
#entry {
    margin: 2px 8px;
    padding: 6px;
    border-radius: 10px;
    background: transparent;
}
#entry:selected {
    background-color: rgba(203, 166, 247, 0.85);
    color: #1e1e2e;
}
#entry:selected #text { color: #1e1e2e; }
#img { margin-right: 8px; }
EOF

echo "=== dunst ==="
w etc/skel/.config/dunst/dunstrc <<'EOF'
[global]
monitor = 0
follow = mouse
width = 380
height = 140
origin = top-right
offset = 14x14
scale = 0
notification_limit = 6
frame_width = 2
frame_color = "#cba6f7"
corner_radius = 12
font = JetBrainsMono Nerd Font 10
background = "#1e1e2eee"
foreground = "#cdd6f4"
timeout = 5
icon_position = left
max_icon_size = 42

[urgency_low]
background = "#181825ee"
foreground = "#a6adc8"
frame_color = "#313244"

[urgency_normal]
background = "#1e1e2eee"
foreground = "#cdd6f4"
frame_color = "#cba6f7"

[urgency_critical]
background = "#2a2033ee"
foreground = "#cdd6f4"
frame_color = "#f38ba8"
timeout = 0
EOF

echo "=== GTK settings (theme/icons/cursor/dark) ==="
w etc/skel/.config/gtk-3.0/settings.ini <<'EOF'
[Settings]
gtk-theme-name = Catppuccin-Mocha
gtk-icon-theme-name = Papirus-Dark
gtk-cursor-theme-name = Bibata-Modern-Ice
gtk-cursor-theme-size = 22
gtk-font-name = Noto Sans 10
gtk-application-prefer-dark-theme = true
gtk-enable-animations = true
EOF
w etc/skel/.config/gtk-4.0/settings.ini <<'EOF'
[Settings]
gtk-theme-name = Catppuccin-Mocha
gtk-icon-theme-name = Papirus-Dark
gtk-cursor-theme-name = Bibata-Modern-Ice
gtk-cursor-theme-size = 22
gtk-font-name = Noto Sans 10
gtk-application-prefer-dark-theme = true
EOF

echo "=== wallpaper scripts ==="
w usr/local/bin/bnasec-wallpaper 755 <<'EOF'
#!/bin/bash
# restore last chosen wallpaper or default
CFG="$HOME/.config/bnasec/wallpaper-choice"
BGDIR=/usr/share/backgrounds/bnasec
swww-daemon --format xrgb >/dev/null 2>&1 &
sleep 0.4
if [ -f "$CFG" ] && [ -f "$BGDIR/$(cat "$CFG")" ]; then
    IMG="$BGDIR/$(cat "$CFG")"
else
    IMG="$BGDIR/bnasec-mocha-aurora.jpg"
fi
swww img "$IMG" --transition-type grow --transition-pos center --transition-duration 1.4 --transition-fps 60
EOF
w usr/local/bin/bnasec-wallpicker 755 <<'EOF'
#!/bin/bash
# pick a wallpaper via wofi (exec from keybind or launcher)
BGDIR=/usr/share/backgrounds/bnasec
CFG="$HOME/.config/bnasec/wallpaper-choice"
mkdir -p "$HOME/.config/bnasec"
CHOICE=$(ls "$BGDIR" | wofi --dmenu --prompt wallpaper --width 420)
[ -n "$CHOICE" ] && swww img "$BGDIR/$CHOICE" --transition-type grow --transition-pos center --transition-duration 1.4 --transition-fps 60 \
  && basename "$CHOICE" > "$CFG"
EOF

echo "=== zsh + p10k ==="
w etc/skel/.zshrc <<'EOF'
# ================= BNAsec Arch zsh =================
# p10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME"
HISTFILE=$HOME/.zsh_history
HISTSIZE=20000
SAVEHIST=20000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS
setopt AUTO_CD CORRECT
unsetopt BEEP

# completion
autoload -Uz compinit && compinit -d "$HOME/.zcompdump"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# powerlevel10k
[[ -r /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]] && \
  source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh

# plugins
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# aliases
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias ip-a='ip -br a'
alias ports='ss -tulnp'
alias tools='bnasec-tools-banner'

# system info on new terminals
[[ -t 1 ]] && command -v fastfetch >/dev/null && fastfetch

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
cp $R/usr/share/zsh-theme-powerlevel10k/config/p10k-rainbow.zsh $R/etc/skel/.p10k.zsh 2>/dev/null && echo "  p10k rainbow config copied"

echo "=== tools banner (the 6 tools at a glance) ==="
w usr/local/bin/bnasec-tools-banner 755 <<'EOF'
#!/bin/bash
echo -e "\e[38;5;183m╔════════════════════════════════════════╗\e[0m"
echo -e "\e[38;5;183m║   BNAsec Arch — security toolkit       ║\e[0m"
echo -e "\e[38;5;183m╚════════════════════════════════════════╝\e[0m"
printf "  %-14s %s\n" "aircrack-ng" "$(aircrack-ng --help 2>&1 | head -1 | grep -oE '1\.[0-9.]+')"
printf "  %-14s %s\n" "nmap" "$(nmap --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
printf "  %-14s %s\n" "hydra" "$(hydra -V 2>&1 | head -1 | grep -oE 'v[0-9.]+' | head -1)"
printf "  %-14s %s\n" "dirb" "$(dirb 2>&1 | grep -oE 'v[0-9.]+')"
printf "  %-14s %s\n" "sqlmap" "$(sqlmap --version 2>/dev/null)"
printf "  %-14s %s\n" "wpscan" "$(wpscan --version 2>/dev/null | grep -oE 'v[0-9.]+')"
EOF

echo "=== fastfetch config (Mocha) ==="
w etc/skel/.config/fastfetch/config.jsonc <<'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": { "type": "small" },
  "display": { "separator": "  " },
  "modules": [
    { "type": "title", "format": "{user-name-color}{user-name}{default-color} @ {host-name}" },
    "separator",
    { "type": "os", "key": "  OS" },
    { "type": "kernel", "key": "  Kernel" },
    { "type": "uptime", "key": "  Uptime" },
    { "type": "packages", "key": "  Packages" },
    { "type": "shell", "key": "  Shell" },
    { "type": "de", "key": "  DE" },
    { "type": "wm", "key": "  WM" },
    { "type": "terminal", "key": "  Term" },
    { "type": "cpu", "key": "  CPU" },
    { "type": "memory", "key": "  RAM" },
    { "type": "swap", "key": "  Swap" },
    { "type": "disk", "key": "  Root" },
    { "type": "custom", "format": "  BNAsec Arch — persistent, secure, riced" }
  ]
}
EOF

echo "=== motd ==="
w etc/motd <<'EOF'

   BNAsec Arch — Hyprland edition
   user: bna    |  password: bnasec   (change with: passwd)
   sudo ready (wheel)  |  persistence: full root on USB
   SUPER+Return terminal   SUPER+D launcher   SUPER+E files

EOF

echo "RICE PART 1 DONE"
ls -la $R/etc/skel/.config/
