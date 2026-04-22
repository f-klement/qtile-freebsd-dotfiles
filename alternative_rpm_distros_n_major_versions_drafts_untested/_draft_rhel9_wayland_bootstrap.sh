#!/usr/bin/env bash
#
# one-shot bootstrap for a fresh rhel 9 qtile Wayland setup
# this is still quite volatile, as wlroots and mesa are in some versioning conflict 
# and don't work well together making the bootup difficult.
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
[[ -L /snap ]] || ln -s /var/lib/snapd/snap /snap && sleep 10
snap install core direnv

sudo -iu "$TARGET_USER" flatpak remote-add --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

### 3. Qtile (Wayland dev libs + XWayland fallback) ─────────────────────────────
dnf install -y \
  python3 python3.12 polkit-kde-agent-1 python3-devel python3-pip python3-gobject \
  libffi-devel cairo cairo-devel pango pango-devel gobject-introspection-devel \
  wayland-devel wayland-protocols-devel libinput-devel \
  libxkbcommon-devel spice-vdagent python3-cffi \
  fontawesome-fonts open-vm-tools open-vm-tools-desktop \
  python3-dbus libinput-devel acpid python3.12-devel \
  xorg-x11-server-Xwayland hwdata-devel
  libdrm-devel \
  libudev-devel \
  libgbm-devel \
  mesa-libEGL-devel \
  libxkbcommon-devel  \
  mesa-libGLES-devel
pip install xkbcommon

## build dependencies ────────────────────────────────────────

export PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
CFLAGS="-Wno-error" meson setup build --prefix=/usr/local

dnf install expat-devel libffi-devel libxml2-devel doxygen xmlto docbook-utils wayland-protocols-devel

skip_if_installed wlroots bash -lc "
cd /tmp
git clone https://gitlab.freedesktop.org/wlroots/wlroots.git
cd wlroots
# Export CFLAGS to turn off -Werror for packed attributes (and more)
export CFLAGS="-Wno-error=packed -Wno-error"
meson setup build \
  --prefix=/usr/local \
  -Dbackends=drm,libinput,x11 \
  --wrap-mode=forcefallback
ninja -C build
sudo ninja -C build install
"
skip_if_installed seatd bash -lc "
sudo tee /etc/systemd/system/seatd.service > /dev/null <<'EOF'
[Unit]
Description=seatd daemon
After=systemd-logind.service
Requires=systemd-logind.service

[Service]
ExecStart=/usr/local/bin/seatd -g seat
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now seatd
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart seatd

sudo groupadd -f seat
sudo usermod -aG seat $TARGET_USER
newgrp seat
sudo usermod -aG video $TARGET_USER
newgrp video

"

### 3.1 Qtile network header dependency ─────────────────────
dnf install gcc make autoconf automake
skip_if_installed iwconfig bash -lc "
wget https://hewlettpackard.github.io/wireless-tools/wireless_tools.29.tar.gz -P /tmp
cd /tmp
tar xzf wireless_tools.29.tar.gz
cd /tmp/wireless_tools.29
./configure --prefix=/usr/local
make
make install
echo "/usr/local/lib" | tee /etc/ld.so.conf.d/local.conf
ldconfig
"


### 3.2 Qtile core ─────────────────────

sudo -iu "$TARGET_USER" bash <<EOF
set -e
python3.12 -m venv "$QTILE_VENV"
source "$QTILE_VENV/bin/activate"
pip install --upgrade pip
pip install \
  qtile qtile-extras \
  mypy typeshed-client typing_extensions \
  pulsectl dbus-next psutil \
  python-dateutil dbus-fast pulsectl-asyncio \
  pywlroots pywayland xkbcommon
pip install qtile[all]
EOF

cat <<EOF | sudo tee /usr/share/wayland-sessions/qtile.desktop > /dev/null
[Desktop Entry]
Name=Qtile (Wayland)
Comment=Qtile Wayland session (user venv)
Exec=/home/$TARGET_USER/.local/venvs/qtile/bin/qtile start -b wayland
Type=Application
DesktopNames=qtile
Keywords=wm;tiling;windowmanager;wayland
EOF

### 4. Runtime packages & Wayland utilities ────────────────────────────────────
dnf install -y \
  btop gnome-keyring network-manager-applet \
  redshift pulseaudio-utils pavucontrol copyq\
  bluez bluez-libs kitty vlc\
  wl-clipboard wayland-utils
  
### building remainder from scratch ───────────────────────────────────────────────────────
skip_if_installed wlr-randr bash -lc "
cd /tmp
git clone https://github.com/emersion/wlr-randr.git
cd wlr-randr
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
"

skip_if_installed swaybg bash -lc "
cd /tmp
git clone https://github.com/swaywm/swaybg.git
cd swaybg
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
"

skip_if_installed swaylock bash -lc "
cd /tmp
git clone https://github.com/swaywm/swaylock.git
cd swaylock
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
"

skip_if_installed swayidle bash -lc "
cd /tmp
git clone https://github.com/swaywm/swayidle.git
cd swayidle
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
"

### 5. Flatpak GUI apps ───────────────────────────────────────────────────────

su - "$TARGET_USER" -c '
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
'

su - "$TARGET_USER" -c '
flatpak install --user -y flathub \
  io.gitlab.librewolf-community \
  com.brave.Browser \
  com.vscodium.codium \
  com.github.tchx84.Flatseal
'
### 6. Builds from source ──────────────────────────────────────────────────────
# fonts & cursors
sudo bash -lc "
  [[ -d /usr/local/share/fonts/JetBrainsMonoNF ]] || (
    mkdir -p /usr/local/share/fonts/JetBrainsMonoNF
    TMP=\$(mktemp -d)
    curl -L https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
      -o \"\$TMP/jbm.zip\"
    unzip -u \"\$TMP/jbm.zip\" -d /usr/local/share/fonts/JetBrainsMonoNF
    rm -rf \"\$TMP\"
    fc-cache -fv
  )
"

sudo -u "$TARGET_USER" bash -lc "
  [[ -d ~/.icons/Dracula-cursors ]] || mkdir -p ~/.icons
  curl -L https://github.com/dracula/gtk/releases/latest/download/Dracula-cursors.tar.xz \
    | tar -xJf - -C ~/.icons
"


### 7. Wallpapers ─────────────────────────────────────────────────────────────
[[ -d /home/$TARGET_USER/Pictures/wallpapers ]] || \
  git clone https://github.com/f-klement/wallpapers.git /home/$TARGET_USER/Pictures/wallpapers

### 8. Default applications ───────────────────────────────────────────────────
 sudo -u "$TARGET_USER" bash -lc '
   set -e
   XDG_CONFIG_HOME="$HOME/.config"
   mkdir -p "$XDG_CONFIG_HOME"
   # editor
   for mime in text/plain text/x-python text/x-shellscript; do
     xdg-mime default com.vscodium.codium.desktop "$mime"
   done
   # browser
   xdg-settings set default-web-browser com.brave.Browser.desktop
   for scheme in http https; do
     xdg-mime default com.brave.Browser.desktop x-scheme-handler/$scheme
   done
   # media player
   for type in video/mp4 video/x-matroska audio/mpeg audio/x-wav; do
     xdg-mime default vlc.desktop "$type"
   done
 '
if command -v kitty >/dev/null; then
  sudo alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50
  sudo alternatives --set x-terminal-emulator /usr/bin/kitty
fi

echo "✔ Fedora 42 Wayland + Qtile bootstrap complete, use GNU stow and enjoy!"
