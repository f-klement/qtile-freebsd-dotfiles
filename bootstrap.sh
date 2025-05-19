#!/usr/bin/env bash
#
# install.sh ─ one-shot bootstrap for a fresh **Rocky / RHEL 9** workstation
# it includes qtile-x11, picom, various WM utilities, python3.12, a collection of 
# additional repos, snap and flatpak versions of the most heavily used everyday 
# applications to keep them as up-to-date as possible.

set -euo pipefail

### 0. Sanity check ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

### 0. Variables & helpers ─────────────────────────────────────────────────────
TARGET_USER="$(logname)"
QTILE_VENV="/home/$TARGET_USER/.local/venvs/qtile"
export PATH="/usr/local/bin:$PATH"

# wrapper: skip the build if the given command already exists
skip_if_installed() {
  local cmd="$1"; shift
  if command -v "$cmd" >/dev/null; then
    echo "✔ $cmd already installed, skipping."
  else
    "$@"
  fi
}

# Ensure dnf is always non-interactive
if ! grep -q '^defaultyes=True' /etc/dnf/dnf.conf; then
  sed -i '/^\[main\]/a defaultyes=True' /etc/dnf/dnf.conf
fi

### 1. Repos & core packages ──────────────────────────────────────────────────
dnf -y install epel-release flatpak git
dnf -y config-manager --set-enabled crb
dnf -y install rpmfusion-free-release
dnf -y install --nogpgcheck \
  https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm

dnf -y groupupdate core
dnf -y groupupdate multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf -y groupupdate sound-and-video

dnf -y install snapd stow epel-next-release
systemctl enable --now snapd.socket

[[ -L /snap ]] || ln -s /var/lib/snapd/snap /snap && sleep 10
snap refresh
snap install core direnv

dnf -y clean all
dnf -y makecache
dnf -y update

sudo -iu "$TARGET_USER" flatpak remote-add --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

### 2. QTile X11 (per-user venv under Python 3.12) ───────────────────────────────
dnf -y install \
  python3.12 python3.12-devel python3-devel python3-gobject python3-pip \
  libffi-devel cairo cairo-devel pango pango-devel gobject-introspection-devel \
  libXScrnSaver-devel spice-vdagent libxkbcommon libxkbcommon-devel \
  xcb-util-keysyms-devel xcb-util-wm-devel xcb-util-devel libXcursor-devel \
  libXinerama-devel python3-pyopengl fontawesome-fonts open-vm-tools \
  open-vm-tools-desktop papirus-icon-theme

sudo -iu "$TARGET_USER" bash <<EOF
set -e
# force venv with Python 3.12
python3.12 -m venv "$QTILE_VENV"
source "$QTILE_VENV/bin/activate"
pip install --upgrade pip
pip install qtile qtile-extras mypy typeshed-client typing_extensions pulsectl dbus-next psutil
# upgrade these separately
<<<<<<< HEAD
pip install --upgrade python-dateutil dbus-fast pulsectl-asyncio
=======
pip install --upgrade python-dateutil dbus-fast
>>>>>>> refs/remotes/origin/main
EOF

cat >/usr/share/xsessions/qtile.desktop <<'EOF'
[Desktop Entry]
Name=Qtile
Comment=Qtile Tiling Window Manager (Python 3.12, X11)
<<<<<<< HEAD
Exec=/home/$TARGET_USER/.local/venvs/qtile/bin/qtile start
=======
Exec=/home/%u/.local/venvs/qtile/bin/qtile start
>>>>>>> refs/remotes/origin/main
Type=Application
Keywords=wm;tiling
EOF

### 3. Runtime packages, utilities & placeholder compositor ────────────────────────────────
dnf -y install \
  btop gnome-keyring-pam polkit-gnome copyq network-manager-applet \
  redshift i3lock pulseaudio-utils pavucontrol bluez bluez-libs \
  python3-dbus acpid kitty vlc xcompmgr

### 4. Flatpak GUI apps ───────────────────────────────────────────────────────
sudo -iu "$TARGET_USER" flatpak install -y --noninteractive flathub \
  org.flameshot.Flameshot \
  io.gitlab.librewolf-community \
  com.brave.Browser \
  com.vscodium.codium \
  com.github.tchx84.Flatseal

### 5. Builds from source ──────────────────────────────────────────────────────

skip_if_installed dunst bash -lc "
  set -e
  [ -d /tmp/dunst ] && rm -rf /tmp/dunst
  dnf -y install meson ninja-build cmake pkgconfig gdk-pixbuf2-devel libXrandr-devel  \
  wayland-devel wayland-protocols-devel libnotify-devel
  git clone https://github.com/dunst-project/dunst.git --depth 1 /tmp/dunst
  cd /tmp/dunst
  [ -d build ] && rm -rf build
  meson setup build --prefix=/usr/local --buildtype=release
  ninja -C build
  ninja -C build install
"

# 5.2 xss-lock
skip_if_installed xss-lock bash -lc "
  set -e
  [ -d /tmp/xss-lock ] && rm -rf /tmp/xss-lock
  dnf -y install gcc make cmake libX11-devel libXScrnSaver-devel xorg-x11-proto-devel libxcb-devel libxkbcommon-devel
  git clone https://bitbucket.org/raymonad/xss-lock /tmp/xss-lock
  cd /tmp/xss-lock
  cmake . -DCMAKE_INSTALL_PREFIX=/usr
  make -j$(nproc)
  make install
"

# 5.3 variety
skip_if_installed variety bash -lc "
  set -e
  [ -d /tmp/variety ] && rm -rf /tmp/variety
  git clone https://github.com/varietywalls/variety.git /tmp/variety
  dnf -y config-manager --set-enabled epel-testing
  dnf -y install python3-distutils-extra python3-pillow imlib2-devel libcurl-devel libXt-devel
  dnf -y install python3-beautifulsoup4 python3-feedparser python3-requests python3-lxml python3-configobj python3-httplib2
  cd /tmp/variety
  python3 setup.py install
"

# 5.4 feh (variety dependency)
skip_if_installed feh bash -lc "
  set -e
  [ -d /tmp/feh ] && rm -rf /tmp/feh
  git clone https://github.com/derf/feh.git /tmp/feh
  cd /tmp/feh
  make
  make install app=1
"

# 5.5 rofi
skip_if_installed rofi bash -lc "
  set -e
  [ -d /tmp/rofi ] && rm -rf /tmp/rofi
  dnf -y install libxkbcommon-x11-devel xcb-util-cursor-devel startup-notification-devel
  git clone --depth=1 --branch 1.7.3 https://github.com/davatorium/rofi.git /tmp/rofi
  cd /tmp/rofi
  [ -d build ] && rm -rf build
  meson setup build --prefix=/usr/local --buildtype=release
  ninja -C build
  ninja -C build install
"

# 5.6 fonts & cursors
skip_if_installed fc-cache bash -lc "
  set -e
  tmp=\$(mktemp -d)
  curl -L https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o \"\$tmp/jbm.zip\"
  mkdir -p /usr/local/share/fonts/JetBrainsMonoNF
  unzip -u \"\$tmp/jbm.zip\" -d /usr/local/share/fonts/JetBrainsMonoNF
  fc-cache -fv
  rm -rf \"\$tmp\"
"

[[ -d ~/.icons/Dracula-cursors ]] || \
  mkdir -p ~/.icons && \
  curl -L https://github.com/dracula/gtk/releases/latest/download/Dracula-cursors.tar.xz \
    | tar -xJf - -C ~/.icons

# 5.7 direnv (misc utils)
skip_if_installed direnv bash -l <<'EOF'
set -e
curl -sfL https://direnv.net/install.sh | bash
EOF

# 5.8 lxappearance
skip_if_installed lxappearance bash -lc "
  set -e
  dnf -y install gtk2-devel glib2-devel
  [ -d /tmp/lxappearance ] && rm -rf /tmp/lxappearance
  git clone https://github.com/lxde/lxappearance.git /tmp/lxappearance
  cd /tmp/lxappearance
  [ -f Makefile ] && make clean
  ./autogen.sh --prefix=/usr/local
  ./configure --prefix=/usr/local
  make
  make install
"

### 6. Build-time deps & picom ────────────────────────────────────────────────
skip_if_installed picom bash -lc "
  set -e
  [ -d /tmp/picom ] && rm -rf /tmp/picom
  dnf -y groupinstall 'Development Tools'
  dnf -y install dbus-devel libconfig-devel libev-devel libX11-devel libxcb-devel mesa-libGL-devel mesa-libEGL-devel libepoxy-devel meson ninja-build pcre2-devel pixman-devel uthash-devel xcb-util-image-devel xcb-util-renderutil-devel xcb-util-devel xorg-x11-proto-devel asciidoctor
  git clone --depth=1 https://github.com/yshui/picom.git /tmp/picom
  cd /tmp/picom
  [ -d build ] && rm -rf build
  meson setup --buildtype=release build
  ninja -C build
  ninja -C build install
"

dnf -y remove xcompmgr || true

# Wallpapers
[[ -d ~/Pictures/wallpapers ]] || \
  git clone https://github.com/f-klement/wallpapers.git ~/Pictures/wallpapers
  
### 7. Default applications
mkdir -p /home/$TARGET_USER/.config
# Flatpak VSCodium as default editor (for $TARGET_USER)
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default com.vscodium.codium.desktop text/plain
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default com.vscodium.codium.desktop text/x-python
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default com.vscodium.codium.desktop text/x-shellscript
# Flatpak Brave as default browser (for $TARGET_USER)
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-settings set default-web-browser com.brave.Browser.desktop
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default com.brave.Browser.desktop x-scheme-handler/http
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default com.brave.Browser.desktop x-scheme-handler/https
# Kitty as default terminal (system-wide)
if command -v kitty >/dev/null; then
  sudo alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50
  sudo alternatives --set x-terminal-emulator /usr/bin/kitty
fi
# VLC as default video & music player (for $TARGET_USER)
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default vlc.desktop video/mp4
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default vlc.desktop video/x-matroska
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default vlc.desktop audio/mpeg
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default vlc.desktop audio/x-wav

echo "✔ Migration complete!  Use stow . to symlink your dotfiles once you’re settled in."
