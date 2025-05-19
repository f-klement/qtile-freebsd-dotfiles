#!/usr/bin/env bash
#
# install-fedora42-wayland.sh ─ one-shot bootstrap for a fresh Fedora 42 Wayland setup
set -euo pipefail

### 0. Sanity check ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

### 1. Variables & helpers ─────────────────────────────────────────────────────
TARGET_USER="$(logname)"
QTILE_VENV="/home/$TARGET_USER/.local/venvs/qtile"
export PATH="/usr/local/bin:$PATH"

skip_if_installed() {
  local cmd="$1"; shift
  if command -v "$cmd" >/dev/null; then
    echo "✔ $cmd already installed, skipping."
  else
    "$@"
  fi
}

# make DNF non-interactive
if ! grep -q '^assumeyes=True' /etc/dnf/dnf.conf; then
  sed -i '/^\[main\]/a assumeyes=True' /etc/dnf/dnf.conf
fi

### 2. Repos & core packages ────────────────────────────────────────────────────
dnf install -y dnf-plugins-core flatpak snapd git stow papirus-icon-theme dejavu-sans-fonts

# RPM Fusion
dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

dnf update -y

systemctl enable --now snapd.socket
[[ -L /snap ]] || ln -s /var/lib/snapd/snap /snap && sleep 5
snap install core direnv

sudo -iu "$TARGET_USER" flatpak remote-add --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

### 3. Qtile (Wayland dev libs + XWayland fallback) ─────────────────────────────
dnf install -y \
  python3 python3.12 python3-devel python3-pip python3-gobject \
  libffi-devel cairo cairo-devel pango pango-devel gobject-introspection-devel \
  wayland-devel wayland-protocols-devel libinput-devel libseat-devel \
  libxkbcommon-devel spice-vdagent \
  fontawesome-fonts open-vm-tools open-vm-tools-desktop \
  python3-dbus acpid \
  xorg-x11-server-Xwayland    # for XWayland apps

sudo -iu "$TARGET_USER" bash <<EOF
set -e
python3.12 -m venv "$QTILE_VENV"
source "$QTILE_VENV/bin/activate"
pip install --upgrade pip
pip install \
  qtile qtile-extras \
  mypy typeshed-client typing_extensions \
  pulsectl dbus-next psutil \
  python-dateutil dbus-fast pulsectl-asyncio
EOF

cat >/usr/share/wayland-sessions/qtile.desktop <<EOF
[Desktop Entry]
Name=Qtile (Wayland)
Comment=Qtile Tiling Window Manager (via XWayland + native Wayland libs)
Exec=/home/$TARGET_USER/.local/venvs/qtile/bin/qtile start
Type=Application
Keywords=wm;tiling;wayland
EOF

### 4. Runtime packages & Wayland utilities ────────────────────────────────────
dnf install -y \
  btop gnome-keyring polkit-gnome network-manager-applet \
  redshift pulseaudio-utils pavucontrol \
  bluez bluez-libs kitty vlc blueman\
  swaylock swayidle wofi wl-clipboard wayland-utils wlr-randr

### 5. Flatpak GUI apps ───────────────────────────────────────────────────────
sudo -iu "$TARGET_USER" flatpak install -y flathub \
  io.gitlab.librewolf-community \
  com.brave.Browser \
  com.vscodium.codium \
  com.github.tchx84.Flatseal

### 6. Builds from source ──────────────────────────────────────────────────────
# 6.1 dunst (notification daemon works under Wayland via dbus)
skip_if_installed dunst bash -lc "
  set -e
  dnf install -y meson ninja-build cmake pkgconfig gdk-pixbuf2-devel libnotify-devel wayland-devel
  rm -rf /tmp/dunst && git clone --depth 1 https://github.com/dunst-project/dunst.git /tmp/dunst
  cd /tmp/dunst && meson setup build --prefix=/usr/local --buildtype=release
  ninja -C build && ninja -C build install
"

# 6.2 variety (wallpaper changer; note: fallback via swaybg)
skip_if_installed variety bash -lc "
  set -e
  dnf install -y python3-distutils-extra python3-pillow imlib2-devel libcurl-devel libXt-devel
  rm -rf /tmp/variety && git clone https://github.com/varietywalls/variety.git /tmp/variety
  cd /tmp/variety && python3 setup.py install
"

# 6.3 feh (still needed by variety, even on Wayland)
skip_if_installed feh bash -lc "
  set -e
  rm -rf /tmp/feh && git clone https://github.com/derf/feh.git /tmp/feh
  cd /tmp/feh && make && make install app=1
"

# 6.4 wofi is installed via DNF; we skip rofi entirely

# 6.5 fonts & cursors
skip_if_installed fc-cache bash -lc "
  set -e
  TMP=\$(mktemp -d)
  curl -L https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o \"\$TMP/jbm.zip\"
  mkdir -p /usr/local/share/fonts/JetBrainsMonoNF
  unzip -u \"\$TMP/jbm.zip\" -d /usr/local/share/fonts/JetBrainsMonoNF
  fc-cache -fv && rm -rf \"\$TMP\"
"
sudo -u "$TARGET_USER" bash -lc "
  [[ -d ~/.icons/Dracula-cursors ]] || mkdir -p ~/.icons
  curl -L https://github.com/dracula/gtk/releases/latest/download/Dracula-cursors.tar.xz \
    | tar -xJf - -C ~/.icons
"

### 7. Wallpapers ─────────────────────────────────────────────────────────────
sudo -u "$TARGET_USER" bash -lc "
  [[ -d ~/Pictures/wallpapers ]] || git clone https://github.com/f-klement/wallpapers.git ~/Pictures/wallpapers
"

### 8. Default applications ───────────────────────────────────────────────────
XDG_CFG="/home/$TARGET_USER/.config"
sudo -u "$TARGET_USER" mkdir -p "$XDG_CFG"

# VSCodium as editor
for mime in text/plain text/x-python text/x-shellscript; do
  sudo -u "$TARGET_USER" XDG_CONFIG_HOME="$XDG_CFG" \
    xdg-mime default com.vscodium.codium.desktop "$mime"
done

# Brave as browser
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="$XDG_CFG" \
  xdg-settings set default-web-browser com.brave.Browser.desktop
for scheme in http https; do
  sudo -u "$TARGET_USER" XDG_CONFIG_HOME="$XDG_CFG" \
    xdg-mime default com.brave.Browser.desktop x-scheme-handler/$scheme
done

# Kitty as terminal
if command -v kitty >/dev/null; then
  alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50
  alternatives --set x-terminal-emulator /usr/bin/kitty
fi

# VLC as media player
for type in video/mp4 video/x-matroska audio/mpeg audio/x-wav; do
  sudo -u "$TARGET_USER" XDG_CONFIG_HOME="$XDG_CFG" \
    xdg-mime default vlc.desktop "$type"
done

echo "✔ Fedora 42 Wayland + Qtile bootstrap complete!  Log into the “Qtile (Wayland)” session and enjoy."
