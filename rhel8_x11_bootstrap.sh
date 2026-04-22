#!/usr/bin/env bash
#
# install.sh ─ one-shot bootstrap for a fresh **Rocky / RHEL 8** workstation
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
dnf -y config-manager --set-enabled powertools
dnf -y install rpmfusion-free-release
dnf -y install --nogpgcheck \
  https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm

dnf -y groupupdate core
dnf -y groupupdate multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf -y groupupdate sound-and-video

dnf -y install snapd stow #epel-next-release
dnf -y install papirus-icon-theme dejavu-sans-fonts
#systemctl enable --now snapd.socket

#[[ -L /snap ]] || ln -s /var/lib/snapd/snap /snap && sleep 10
#snap refresh
#snap install core direnv

dnf -y clean all
dnf -y makecache
dnf -y update

sudo -iu "$TARGET_USER" flatpak remote-add --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

snap install codium --classic

### 2. QTile X11 (per-user venv under Python 3.12) ───────────────────────────────
dnf -y install \
  python3.12 python3.12-devel polkit-kde python3-devel python3-gobject python3-pip \
  libffi-devel cairo cairo-devel pango pango-devel gobject-introspection-devel \
  libXScrnSaver-devel spice-vdagent libxkbcommon libxkbcommon-devel \
  xcb-util-keysyms-devel xcb-util-wm-devel xcb-util-devel libXcursor-devel \
  libXinerama-devel python3-pyopengl fontawesome-fonts open-vm-tools \
  open-vm-tools-desktop adwaita-qt5 xorg-x11-server-Xorg \
  xorg-x11-utils xorg-x11-apps ranger xorg-x11-fonts-misc yad qt5ct \
  xorg-x11-drv-vmware xorg-x11-server-Xvfb xorg-x11-server-Xwayland


sudo -iu "$TARGET_USER" bash <<EOF
set -e
# force venv with Python 3.12
python3.12 -m venv "$QTILE_VENV"
source "$QTILE_VENV/bin/activate"
pip install --upgrade pip
pip install qtile qtile-extras mypy typeshed-client typing_extensions pulsectl dbus-next psutil
# upgrade these separately
pip install --upgrade python-dateutil dbus-fast pulsectl-asyncio pangocffi cairocffi
EOF

cat >/usr/share/xsessions/qtile.desktop <<'EOF'
[Desktop Entry]
Name=Qtile
Comment=Qtile Tiling Window Manager (Python 3.12, X11)
Exec=/home/$TARGET_USER/.local/venvs/qtile/bin/qtile start
Type=Application
Keywords=wm;tiling
EOF

### 3. Runtime packages, utilities & placeholder compositor ────────────────────────────────
dnf -y install \
  btop gnome-keyring-pam copyq network-manager-applet \
  redshift pulseaudio-utils pavucontrol bluez bluez-libs \
  python3-dbus acpid kitty vlc xcompmgr powerline-fonts 


### 4. Flatpak GUI apps ───────────────────────────────────────────────────────
su - "$TARGET_USER" -c '
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
'

su - "$TARGET_USER" -c '
flatpak install --user -y flathub \
  io.gitlab.librewolf-community \
  com.brave.Browser \
  com.github.tchx84.Flatseal \
  org.flameshot.Flameshot \
  md.obsidian.Obsidian
'

### 5. Builds from source ──────────────────────────────────────────────────────
# 5.0 i3-lock
install_i3lock() {
  set -e
  # 1. Install all build-time dependencies
  dnf install -y pkgconf-pkg-config meson ninja-build pam-devel cairo-devel \
    libev-devel libX11-devel libxkbcommon-devel libxkbcommon-x11-devel \
    libxcb-devel xcb-util-devel xcb-util-image-devel xcb-util-keysyms-devel \
    xcb-util-renderutil-devel xcb-util-wm-devel xcb-util-cursor-devel \
    xorg-x11-util-macros autoconf automake libtool copyq

  # 2. Build & install xcb-util-xrm
  rm -rf /tmp/xcb-util-xrm
  git clone https://github.com/Airblader/xcb-util-xrm.git --depth 1 /tmp/xcb-util-xrm
  git clone https://gitlab.freedesktop.org/xorg/util/xcb-util-m4.git /tmp/xcb-util-xrm/m4
  cd /tmp/xcb-util-xrm
  ./autogen.sh
  ./configure --prefix=/usr --disable-dependency-tracking
  make -j"$(nproc)"
  make install

  # 3. Build & install i3lock
  rm -rf /tmp/i3lock
  git clone https://github.com/i3/i3lock.git --depth 1 /tmp/i3lock
  cd /tmp/i3lock
  rm -rf build
  meson setup build --prefix=/usr --buildtype=release
  ninja -C build
  ninja -C build install
}
skip_if_installed i3lock install_i3lock

# 5.1 dunst

#modern meson and ninja calls:
# 0) create + activate a Python 3.12 venv for Meson
python3.12 -m venv /tmp/meson-venv
/tmp/meson-venv/bin/pip install --upgrade meson>=0.60.0 ninja packaging

install_dunst() {
# 1) clean any old clone
[ -d /tmp/dunst ] && rm -rf /tmp/dunst
# 2) install the C deps
dnf -y install \
  pkgconfig gdk-pixbuf2-devel libXrandr-devel \
  wayland-devel wayland-protocols-devel \
  libnotify-devel

# 3) clone latest dunst
  git clone --depth 1 https://github.com/dunst-project/dunst.git /tmp/dunst
  cd /tmp/dunst

# 4) inject a GLib<2.58 fallback for g_rc_box_*
  sed -i '1i\
/* Compatibility for GLib < 2.58: fallback to g_slice_ */\
#include <glib.h> \
#ifndef g_rc_box_alloc \
#define g_rc_box_alloc(size)      g_slice_alloc(size) \
#endif \
#ifndef g_rc_box_acquire \
#define g_rc_box_acquire(ptr)     (ptr) \
#endif \
#ifndef g_rc_box_release_full \
#define g_rc_box_release_full(p,d) ((d)(p)) \
#endif' src/draw.c

# 5) build & install via Meson/Ninja
  /tmp/meson-venv/bin/meson setup build --prefix=/usr/local --buildtype=release
  /tmp/meson-venv/bin/meson compile -C build
  /tmp/meson-venv/bin/meson install -C build
}
skip_if_installed dunst install_dunst

# 5.2 xss-lock
install_xss_lock() {
  [ -d /tmp/xss-lock ] && rm -rf /tmp/xss-lock
  dnf -y install gcc make cmake libX11-devel libXScrnSaver-devel xorg-x11-proto-devel \
    libxcb-devel libxkbcommon-devel
  git clone https://bitbucket.org/raymonad/xss-lock /tmp/xss-lock
  cd /tmp/xss-lock
  cmake . -DCMAKE_INSTALL_PREFIX=/usr
  make -j"$(nproc)"
  make install
}
skip_if_installed xss-lock install_xss_lock

# 5.3 feh (variety dependency)
install_feh() {
  [ -d /tmp/feh ] && rm -rf /tmp/feh
  git clone https://github.com/derf/feh.git /tmp/feh
  cd /tmp/feh
  make -j"$(nproc)"
  make install app=1
}
skip_if_installed feh install_feh

# 5.4 rofi
install_rofi() {
  [ -d /tmp/rofi ] && rm -rf /tmp/rofi
  dnf -y install libxkbcommon-x11-devel xcb-util-cursor-devel flex bison startup-notification-devel
  git clone --depth=1 --branch 1.7.3 https://github.com/davatorium/rofi.git /tmp/rofi
  cd /tmp/rofi
  [ -d build ] && rm -rf build

  source /tmp/meson-venv/bin/activate 
  pip install flex bison

  /tmp/meson-venv/bin/meson setup build --prefix=/usr/local --buildtype=release
  /tmp/meson-venv/bin/ninja -C build
  /tmp/meson-venv/bin/ninja -C build install
}
skip_if_installed rofi install_rofi

# 5.5 fonts & cursors
FONT_NAME="JetBrainsMono Nerd Font"
FONT_DIR="$TARGET_USER/.local/share/fonts"
FONT_ZIP="JetBrainsMono.zip"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$FONT_ZIP"

# Check if the font is already installed
if fc-list | grep -qi "$FONT_NAME"; then
    echo "'$FONT_NAME' is already installed. Skipping download."
else
    echo " Installing '$FONT_NAME'..."
    mkdir -p "$FONT_DIR"
    cd "$FONT_DIR" || exit 1

    wget "$FONT_URL" -O "$FONT_ZIP"
    unzip -o "$FONT_ZIP"
    rm "$FONT_ZIP"

    echo " Rebuilding font cache..."
    fc-cache -fv

    echo "'$FONT_NAME' installed successfully."
fi

sudo -u "$TARGET_USER" bash -lc "
  [[ -d ~/.icons/Dracula-cursors ]] || mkdir -p ~/.icons
  curl -L https://github.com/dracula/gtk/releases/latest/download/Dracula-cursors.tar.xz \
    | tar -xJf - -C ~/.icons
"
# 5.6 direnv (misc utils)
install_direnv() {
  curl -sfL https://direnv.net/install.sh | bash
}
skip_if_installed direnv install_direnv

# 5.7 lxappearance
install_lxappearance() {
  dnf -y install gtk2-devel glib2-devel
  [ -d /tmp/lxappearance ] && rm -rf /tmp/lxappearance
  git clone https://github.com/lxde/lxappearance.git /tmp/lxappearance
  cd /tmp/lxappearance
  [ -f Makefile ] && make clean
  ./autogen.sh --prefix=/usr/local
  ./configure --prefix=/usr/local
  make -j"$(nproc)"
  make install
}
skip_if_installed lxappearance install_lxappearance

### 6. Build-time deps & picom ────────────────────────────────────────────────
install_picom() {
  # 0. Make sure clang is there
  dnf -y groupinstall 'Development Tools'
  dnf -y install clang clang-devel llvm

  # 1. Build & install libconfig-1.7+ system-wide
  [ -d /tmp/libconfig ] && rm -rf /tmp/libconfig
  git clone https://github.com/hyperrealm/libconfig.git /tmp/libconfig
  cd /tmp/libconfig
  autoreconf -i
  ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --libdir=/usr/lib64
  make -j"$(nproc)"
  make install
  sudo ldconfig

  # 2. Install all the other deps you still need via dnf
  dnf -y install \
    dbus-devel \
    libev-devel \
    libX11-devel \
    libxcb-devel \
    mesa-libGL-devel \
    mesa-libEGL-devel \
    libepoxy-devel \
    meson \
    ninja-build \
    pcre2-devel \
    pixman-devel \
    uthash-devel \
    xcb-util-image-devel \
    xcb-util-renderutil-devel \
    xcb-util-devel \
    xorg-x11-proto-devel \
    asciidoctor \
    texinfo

  # 3. Clone, build & install picom
  [ -d /tmp/picom ] && rm -rf /tmp/picom
  git clone --branch v11.2 --depth=1 https://github.com/yshui/picom.git /tmp/picom
  cd /tmp/picom
  [ -d build ] && rm -rf build
  /tmp/meson-venv/bin/meson setup build \
    --prefix=/usr \
    -Dbuildtype=release \
    -Dwerror=false
 /tmp/meson-venv/bin/ninja -C build
/tmp/meson-venv/bin/ninja -C build install
}
skip_if_installed picom install_picom

dnf -y remove xcompmgr || true

# Wallpapers
[[ -d /home/$TARGET_USER/Pictures/wallpapers ]] || \
  git clone https://github.com/f-klement/wallpapers.git /home/"$TARGET_USER"/Pictures/wallpapers

### USER SPACE TOOLS ###

### 7. Node & Bun 4 TS and UV 4 Python --------------------------------

install_nvm() {
  dnf install -y libatomic
# The single quotes around 'EOF' prevent root from expanding $HOME early.
  sudo -i -u "$TARGET_USER" bash << 'EOF'
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    export NVM_DIR="$HOME/.nvm"               
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    nvm install node
    nvm use node
EOF
}
skip_if_installed nvm install_nvm

install_bun() {
  sudo -i -u "$TARGET_USER" bash << 'EOF'
    curl -fsSL https://bun.com/install | bash
    echo 'export BUN_INSTALL="$HOME/.bun"' >> "$HOME/.zshrc"
    echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> "$HOME/.zshrc"
EOF
}
skip_if_installed bun install_bun

install_uv() {
  sudo -i -u "$TARGET_USER" bash << 'EOF'
    curl -LsSf https://astral.sh/uv/install.sh | sh
    echo 'eval "$(uv generate-shell-completion zsh)"' >> "$HOME/.zshrc"
    echo 'eval "$(uvx --generate-shell-completion zsh)"' >> "$HOME/.zshrc"
EOF
}
skip_if_installed uv install_uv

### 8.CLIs & TUIs ---------------------------------------------

# fzf
install_fzf() {
  sudo -i -u "$TARGET_USER" bash << 'EOF'
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --all
EOF
}
skip_if_installed fzf install_fzf

# ripgrep

install_ripgrep() {
  # Rust for rg
  # Rustup requires -y to be non-interactive
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
  cd /tmp
  [ -d ripgrep ] && rm -rf ripgrep
  git clone https://github.com/BurntSushi/ripgrep
  cd ripgrep
  cargo build --release
  mv ./target/release/rg /usr/local/bin/
}
skip_if_installed ripgrep install_ripgrep

#docker & lazydocker

install_docker() {
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin.x86_64
  systemctl enable --now docker
  usermod -aG docker "$TARGET_USER"
}
skip_if_installed docker install_docker

install_lazydocker() {
  sudo -i -u "$TARGET_USER" bash << 'EOF'
    curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash  
    # Outer single quotes protect the inner double quotes natively!
    echo 'alias ld="lazydocker"' >> "$HOME/.zshrc"
EOF
}
skip_if_installed lazydocker install_lazydocker

# Homebrew for linux, for modern Compilers and Buildchains

install_brew() {
  sudo -i -u "$TARGET_USER" bash << 'EOF'
    # Force non-interactive so brew doesn't stall waiting for the Enter key
    export NONINTERACTIVE=1
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"' >> "$HOME/.zshrc"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
    brew install gcc
EOF
}
skip_if_installed brew install_brew

### 9. System Tools & API Testing ──────────────────────────────────────────────

# Bruno for apis

install_bruno() {
  dnf install -y fuse qt5-qtbase qt5-qtbase-gui
  npm install -g @usebruno/cli
  
  local AIL_URL
  AIL_URL=$(curl -s https://api.github.com/repos/TheAssassin/AppImageLauncher/releases | \
    jq -r '[.[] | select(.prerelease == false and (.tag_name | test("alpha|beta|rc"; "i") | not))][0] | .assets[] | select(.name | endswith("x86_64.rpm")) | .browser_download_url' | head -n 1)

  echo "Downloading Stable AppImageLauncher from: $AIL_URL"
  curl -L "$AIL_URL" -o /tmp/appimagelauncher.rpm
  dnf localinstall -y /tmp/appimagelauncher.rpm
  rm /tmp/appimagelauncher.rpm

  # Download the Bruno AppImage for the target user
  sudo -i -u "$TARGET_USER" bash << 'EOF'
    BRUNO_URL=$(curl -s https://api.github.com/repos/usebruno/bruno/releases | \
      jq -r '[.[] | select(.prerelease == false and (.tag_name | test("alpha|beta|rc"; "i") | not))][0] | .assets[] | select(.name | contains("x86_64") and endswith(".AppImage")) | .browser_download_url' | head -n 1)

    mkdir -p "$HOME/Applications"
    curl -L "$BRUNO_URL" -o "$HOME/Applications/Bruno.AppImage"
    chmod +x "$HOME/Applications/Bruno.AppImage"
    echo "Please register Bruno on the first launch systemwide with Appimage Laucher at: HOME/Applications/Bruno.AppImage"
EOF
}
skip_if_installed bruno install_bruno

# system cleanup utilities

install_bleachbit() {
  dnf -y install epel-release 
  dnf install -y bleachbit
}
skip_if_installed bleachbit install_bleachbit

install_gdu() {
  cd /tmp
  curl -L https://github.com/dundee/gdu/releases/latest/download/gdu_linux_amd64.tgz | tar xz
  chmod +x gdu_linux_amd64
  mv gdu_linux_amd64 /usr/bin/gdu
}
skip_if_installed gdu install_gdu

### 10. Default applications
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

echo "Migration complete!  Use stow . to symlink your dotfiles once you’re settled in."
