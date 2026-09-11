#!/usr/bin/env bash
#
# install.sh ─ one-shot bootstrap for a fresh **Rocky / RHEL 8** workstation
# qtile-x11, picom, WM utilities, python3.12, extra repos, and the everyday
# applications, preferring upstream RPM repos over snap/flatpak where one exists
# (snap and flatpak both went badly stale in practice: the codium snap sat 7
# months behind, the Brave flatpak accumulated two unused runtime versions).
#
# Containers: rootless podman with NATIVE kernel overlay, driven by the docker
# CLI via DOCKER_HOST. There is no docker daemon - see install_podman for why the
# two cannot coexist on EL8.
#
# Section 9.5 carries the session/memory hardening from the 2026-09-07 freeze
# investigation; see archive/docs/ for the reasoning behind each item.
#
# snapd is still installed below but nothing uses it any more - safe to drop if
# you have no snap-only tooling left.

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

# --- portability layer --------------------------------------------------------
# Most of what follows is EL8-specific only because EL8 is old. Rather than
# hardcoding those workarounds, detect the platform and probe for capabilities,
# so this script degrades to something much shorter on EL9/10 or Fedora.
. /etc/os-release
DISTRO_ID="${ID:-unknown}"; DISTRO_VER="${VERSION_ID%%.*}"
echo "platform: $DISTRO_ID $DISTRO_VER (kernel $(uname -r))"

# CRB/PowerTools changed name in EL9.
case "$DISTRO_VER" in
  8) CRB_REPO="powertools" ;;
  *) CRB_REPO="crb" ;;
esac

# is a package available in any enabled repo?
have_pkg() { dnf -q list available "$1" >/dev/null 2>&1 || rpm -q "$1" >/dev/null 2>&1; }

# Install from the distro if it exists there, otherwise fall back to the
# from-source builder. On EL8 nearly everything below falls through to source;
# on EL9+ most of these are packaged and the source builds simply never run.
pkg_or_build() {
  local cmd="$1" pkg="$2"; shift 2
  if command -v "$cmd" >/dev/null; then echo "✔ $cmd present, skipping."; return; fi
  if have_pkg "$pkg"; then
    echo "→ $cmd: installing packaged $pkg"
    dnf -y install "$pkg" && return
  fi
  echo "→ $cmd: not packaged here, building from source"
  "$@"
}

# --- capability probes --------------------------------------------------------
# zswap: pick the densest zpool and best compressor the RUNNING kernel actually
# supports, instead of assuming. Getting this wrong fails SILENTLY - the kernel
# logs "zpool X not available, using default zbud" and carries on degraded.
KCONF="/boot/config-$(uname -r)"
ZSWAP_ZPOOL=""; ZSWAP_COMP=""
if [[ -r $KCONF ]]; then
  for z in z3fold zsmalloc zbud; do
    grep -q "^CONFIG_${z^^}=" "$KCONF" && { ZSWAP_ZPOOL="$z"; break; }
  done
  for c in zstd lz4 lzo; do
    grep -q "^CONFIG_CRYPTO_${c^^}=" "$KCONF" && { ZSWAP_COMP="$c"; break; }
  done
fi
echo "zswap capability: zpool=${ZSWAP_ZPOOL:-none} compressor=${ZSWAP_COMP:-none}"

# Native (kernel) overlay for rootless containers, vs the ~2-5x slower
# fuse-overlayfs. EL8 backports this; newer kernels have it natively.
NATIVE_OVERLAY=0
_t=$(mktemp -d); mkdir -p "$_t"/{l,u,w,m}; chown -R "$TARGET_USER" "$_t"; chmod 755 "$_t"
runuser -u "$TARGET_USER" -- unshare --user --map-root-user --mount sh -c \
  "mount -t overlay overlay -o lowerdir=$_t/l,upperdir=$_t/u,workdir=$_t/w $_t/m" \
  2>/dev/null && NATIVE_OVERLAY=1
rm -rf "$_t"
echo "rootless native overlay: $([[ $NATIVE_OVERLAY == 1 ]] && echo yes || echo NO - would fall back to fuse-overlayfs)"

# qtile Wayland readiness. Not viable on EL8: wlroots/wayland-protocols/seatd/
# Xwayland are unpackaged, AND the session arrives via xrdp->Xvnc which is X11
# by construction, with no Wayland-capable remote server available
# (gnome-remote-desktop and wayvnc both absent). On EL9+ both halves become
# possible, so report rather than assume.
WAYLAND_READY=1
for p in wlroots-devel wayland-protocols seatd xorg-x11-server-Xwayland; do
  have_pkg "$p" || { WAYLAND_READY=0; break; }
done
have_pkg gnome-remote-desktop || WAYLAND_READY=0
echo "qtile-wayland viable: $([[ $WAYLAND_READY == 1 ]] && echo 'yes - see autostart_wayland.sh' || echo 'no - staying on X11')"

# Ensure dnf is always non-interactive
if ! grep -q '^defaultyes=True' /etc/dnf/dnf.conf; then
  sed -i '/^\[main\]/a defaultyes=True' /etc/dnf/dnf.conf
fi

### 1. Repos & core packages ──────────────────────────────────────────────────
dnf -y install epel-release flatpak git
dnf -y config-manager --set-enabled "$CRB_REPO"
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

# VSCodium from the project's own RPM repo. The snap (classic confinement) went
# 7 months without refreshing in practice, and codium is in neither Rocky nor EPEL.
rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
cat > /etc/yum.repos.d/vscodium.repo <<'VSCODIUM_REPO'
[gitlab.com_paulcarroty_vscodium_repo]
name=download.vscodium.com
baseurl=https://download.vscodium.com/rpms/
enabled=1
gpgcheck=1
# repo_gpgcheck=0 deliberately: =1 makes dnf build a throwaway gpgme keyring in
# /var/tmp and hang respawning gpg-agent. gpgcheck=1 still verifies every RPM.
repo_gpgcheck=0
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
VSCODIUM_REPO
dnf -y install codium

# Brave from its own RPM repo rather than flatpak: the flatpak lags upstream and
# accumulated two stale runtime versions in practice.
dnf -y config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
rpmkeys --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc || true
dnf -y install brave-browser

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
pkg_or_build i3lock i3lock install_i3lock

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
pkg_or_build dunst dunst install_dunst

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
pkg_or_build xss-lock xss-lock install_xss_lock

# 5.3 feh (variety dependency)
install_feh() {
  [ -d /tmp/feh ] && rm -rf /tmp/feh
  git clone https://github.com/derf/feh.git /tmp/feh
  cd /tmp/feh
  make -j"$(nproc)"
  make install app=1
}
pkg_or_build feh feh install_feh

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
pkg_or_build rofi rofi install_rofi

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
pkg_or_build direnv direnv install_direnv

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
pkg_or_build lxappearance lxappearance install_lxappearance

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
pkg_or_build picom picom install_picom

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
pkg_or_build fzf fzf install_fzf

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
pkg_or_build ripgrep ripgrep install_ripgrep

#docker & lazydocker

# Rootless podman, driven by the docker CLI via DOCKER_HOST.
#
# docker-ce and podman CANNOT coexist on EL8: containerd.io declares
# "Obsoletes: runc" + "Conflicts: runc", while podman's containers-common has a
# hard "Requires: runc". But docker-ce-cli and docker-compose-plugin are
# standalone Go binaries needing nothing from the daemon, so install the CLIENT
# from Docker's repo and point it at podman's Docker-compatible socket. Existing
# compose files and project scripts then work unmodified.
install_podman() {
  dnf -y install podman skopeo buildah crun

  # docker CLIENT only. Repo disabled afterwards so a later update cannot drag
  # the daemon back in and re-break podman.
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  dnf -y --setopt=install_weak_deps=False install docker-ce-cli docker-compose-plugin
  dnf -y config-manager --set-disabled docker-ce-stable docker-ce-test docker-ce-nightly

  loginctl enable-linger "$TARGET_USER"
  grep -q "^$TARGET_USER:" /etc/subuid 2>/dev/null || \
    usermod --add-subuids 200000-265535 --add-subgids 200000-265535 "$TARGET_USER"

  # cgroup v2 delegation: rootless Kubernetes (minikube --driver=podman) needs
  # cpu/cpuset/io on top of the default memory/pids.
  install -d /etc/systemd/system/user@.service.d
  cat > /etc/systemd/system/user@.service.d/delegate.conf <<'DELEGATE'
[Service]
Delegate=cpu cpuset io memory pids
DELEGATE
  systemctl daemon-reload

  # NATIVE kernel overlay, NOT fuse-overlayfs. RHEL 8 backports unprivileged
  # overlay mounts; the packaged rootless default is fuse-overlayfs, which is
  # ~2-5x slower on metadata. Omitting mount_program selects the kernel path.
  sed -i -E 's|^(\s*)(mount_program\s*=.*)$|\1# disabled for native overlay: \2|' \
    /etc/containers/storage.conf 2>/dev/null || true
  install -d -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.config/containers"
  cat > "/home/$TARGET_USER/.config/containers/storage.conf" <<'STORAGE'
[storage]
driver = "overlay"
[storage.options]
# mount_program intentionally unset -> native kernel overlay
[storage.options.overlay]
ignore_chown_errors = "true"
STORAGE
  chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/containers/storage.conf"

  sudo -iu "$TARGET_USER" systemctl --user enable --now podman.socket || true
  if sudo -iu "$TARGET_USER" podman info --format '{{.Store.GraphOptions}}' | grep -qi fuse; then
    echo "WARNING: fuse-overlayfs in use - check storage.conf"
  else
    echo "podman storage: native kernel overlay"
  fi
}
skip_if_installed podman install_podman

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
pkg_or_build bleachbit bleachbit install_bleachbit

install_gdu() {
  cd /tmp
  curl -L https://github.com/dundee/gdu/releases/latest/download/gdu_linux_amd64.tgz | tar xz
  chmod +x gdu_linux_amd64
  mv gdu_linux_amd64 /usr/bin/gdu
}
pkg_or_build gdu gdu install_gdu

### 9.5 Session & memory hardening ─────────────────────────────────────────────
# Everything below came out of diagnosing a session that froze under load while
# a colleague's stock GNOME on identical hardware did not. See
# archive/docs/2026-09-07-session-stability-investigation.md for the full write-up.

# --- 9.5.1 gnome-session: stop launching a full GNOME under qtile -------------
# The session runs gnome-session-binary as its anchor (a watchdog monitors that
# process), which by default pulls in 19 gsd-* daemons plus tracker AND then
# qtile on top - strictly heavier than the stock GNOME being compared against.
# /usr/local/share precedes /usr/share in XDG_DATA_DIRS, so this shadows the
# RPM-owned file without modifying it. gnome-session still starts and keeps its
# place in the process tree; only its child list shrinks.
install -d /usr/local/share/gnome-session/sessions
sed 's|^RequiredComponents=.*|RequiredComponents=org.gnome.SettingsDaemon.XSettings;org.gnome.SettingsDaemon.Keyboard;org.gnome.SettingsDaemon.MediaKeys;|' \
  /usr/share/gnome-session/sessions/gnome.session \
  > /usr/local/share/gnome-session/sessions/gnome.session
chmod 644 /usr/local/share/gnome-session/sessions/gnome.session
# Also place it at the user path: which of these gnome-session actually reads is
# build-dependent, and on this EL8 build /usr/local/share alone did NOT take.
install -d -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.config/gnome-session/sessions"
cp /usr/local/share/gnome-session/sessions/gnome.session \
   "/home/$TARGET_USER/.config/gnome-session/sessions/gnome.session"
chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/gnome-session/sessions/gnome.session"
# Kept: XSettings (GTK theme/font/DPI), Keyboard (XKB layout - German here),
# MediaKeys. Dropped incl. org.gnome.Shell (was started then killed by
# bin/starting-qtile.sh), Power (source of recurring "Unable to inhibit system"
# spam), Clipboard (copyq already does this), and Housekeeping (NOTE: this loses
# the low-disk-space warning).

# --- 9.5.2 disable tracker and other unused autostarts ------------------------
# tracker indexes $HOME on a dev box and tracker-extract crashed 25+ times in a
# single afternoon here. It is BOTH an XDG autostart AND a systemd user unit AND
# D-Bus activated, so all three paths need closing.
# A bare "[Desktop Entry]\nHidden=true" is NOT enough: without Type= and Name=
# the file is an invalid desktop entry, GLib rejects it, and gnome-session
# silently falls back to the system copy in /etc/xdg/autostart. Verified with
# strace - gnome-session DOES open the user override, it just discards it.
# X-GNOME-Autostart-enabled=false is the key gnome-session honours directly.
hide_autostart() {
  local dir="$1" name="$2"
  cat > "$dir/$name.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=$name (disabled)
Exec=/bin/true
Hidden=true
X-GNOME-Autostart-enabled=false
NoDisplay=true
ENTRY
  chown "$TARGET_USER:$TARGET_USER" "$dir/$name.desktop"
}

AS="/home/$TARGET_USER/.config/autostart"
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$AS"
for n in tracker-store tracker-miner-fs tracker-miner-apps tracker-extract \
         gnome-software-service gsettings-data-convert gnome-shell-overrides-migration \
         user-dirs-update-gtk orca-autostart; do
  [ -f "/etc/xdg/autostart/$n.desktop" ] || continue
  hide_autostart "$AS" "$n"
done

# The gsd-* plugins are listed in BOTH gnome.session's RequiredComponents AND
# /etc/xdg/autostart/org.gnome.SettingsDaemon.*.desktop (OnlyShowIn=GNOME, and
# gnome-session exports XDG_CURRENT_DESKTOP=GNOME to its children). Trimming the
# session file alone therefore does NOT stop them - they still autostart. Hide
# every plugin except the three worth keeping.
#   XSettings  - GTK theme/font/DPI for every GTK app
#   Keyboard   - XKB layout (German here; losing it is very noticeable)
#   MediaKeys  - holds a D-Bus name some apps query
GSD_KEEP="XSettings Keyboard MediaKeys"
for f in /etc/xdg/autostart/org.gnome.SettingsDaemon.*.desktop; do
  [ -e "$f" ] || continue
  b=$(basename "$f" .desktop); plugin=${b##*.}
  echo "$GSD_KEEP" | grep -qw "$plugin" && continue
  hide_autostart "$AS" "$b"
done
sudo -iu "$TARGET_USER" bash -c '
  systemctl --user mask tracker-store tracker-miner-fs tracker-miner-apps \
                        tracker-extract tracker-writeback 2>/dev/null
  gsettings set org.freedesktop.Tracker.Miner.Files index-recursive-directories "[]"
  gsettings set org.freedesktop.Tracker.Miner.Files index-single-directories "[]"
  gsettings set org.freedesktop.Tracker.Miner.Files enable-monitors false
  gsettings set org.freedesktop.Tracker.Miner.Files crawling-interval -2
' || true

# --- 9.5.3 writeback latency --------------------------------------------------
# tuned's virtual-guest profile sets dirty_ratio=30, which on 7.6 GB allows
# ~2.3 GB of dirty pages to queue before throttling, then flushes to a slow
# virtual disk - a system-wide stall on every docker build / npm install.
# Setting *_bytes zeroes the corresponding *_ratio, which is intended.
cat > /etc/sysctl.d/99-desktop-latency.conf <<'SYSCTL'
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864
# vm.swappiness = 100
#   ^ enable ONLY after confirming zswap is using zsmalloc (see 9.5.4):
#       cat /sys/module/zswap/parameters/zpool
#     Raising it while the pool is zbud pushes more traffic into a badly
#     compressing pool and makes things worse.
SYSCTL
sysctl -p /etc/sysctl.d/99-desktop-latency.conf || true

# --- 9.5.4 zswap ---------------------------------------------------------------
# CONFIG_Z3FOLD is NOT set on the EL8 kernel, so zswap.zpool=z3fold silently
# falls back to zbud (2 pages per zpage, ~1.7:1) - it reserves 20% of RAM and
# gives little back. CONFIG_ZSMALLOC=y is present and packs far denser.
# lzo is the only compressor available: CONFIG_CRYPTO_LZ4 and _ZSTD are unset,
# so zswap.compressor=lz4 would fail the same silent-fallback way.
if command -v grubby >/dev/null; then
  grubby --update-kernel=ALL --remove-args="zswap.enabled zswap.zpool zswap.compressor zswap.max_pool_percent"
  if [[ -n $ZSWAP_ZPOOL && -n $ZSWAP_COMP ]]; then
    grubby --update-kernel=ALL --args="zswap.enabled=1 zswap.zpool=$ZSWAP_ZPOOL zswap.compressor=$ZSWAP_COMP zswap.max_pool_percent=20"
    echo "zswap: zpool=$ZSWAP_ZPOOL compressor=$ZSWAP_COMP"
  else
    echo "zswap: no supported zpool/compressor detected - leaving disabled"
  fi
  echo "zswap staged (needs reboot). Verify: cat /sys/module/zswap/parameters/zpool"
fi

# --- 9.5.5 Brave GPU flags -----------------------------------------------------
# No 3D on this VMware guest: Brave probes vaapi -> zink -> DRM/KMS and fails at
# each, emitting ~40 DRM_IOCTL_MODE_CREATE_DUMB errors per launch. The flatpak
# hid this because Brave auto-picked --disable-gpu-compositing in the sandbox.
# ~/.local/bin precedes /usr/bin, so this wrapper covers shell and PATH launches;
# the .desktop override covers menu launches.
BIN="/home/$TARGET_USER/.local/bin"
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$BIN"
cat > "$BIN/brave-browser" <<'BRAVEWRAP'
#!/usr/bin/env bash
exec /usr/bin/brave-browser-stable \
  --disable-gpu --disable-software-rasterizer --disable-gpu-compositing "$@"
BRAVEWRAP
chmod +x "$BIN/brave-browser"; chown "$TARGET_USER:$TARGET_USER" "$BIN/brave-browser"
APPS="/home/$TARGET_USER/.local/share/applications"
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$APPS"
if [ -f /usr/share/applications/brave-browser.desktop ]; then
  sed 's|^Exec=/usr/bin/brave-browser-stable|Exec=/usr/bin/brave-browser-stable --disable-gpu --disable-software-rasterizer --disable-gpu-compositing|' \
    /usr/share/applications/brave-browser.desktop > "$APPS/brave-browser.desktop"
  chown "$TARGET_USER:$TARGET_USER" "$APPS/brave-browser.desktop"
fi

# NOTE: qtile's glibc allocator tuning (MALLOC_TRIM_THRESHOLD_, MALLOC_ARENA_MAX)
# lives in bin/starting-qtile.sh, and DOCKER_HOST / DOCKER_BUILDKIT=0 in .zshrc -
# both are stowed from this repo, so they need nothing here.

### 9.6 Theming - Rosé Pine, dark, across toolkits ────────────────────────────
# How theming reaches each toolkit in this session (gnome-session + qtile):
#   GTK2/3 + Chromium/Electron : gsd-xsettings (kept alive in 9.5.1) broadcasts
#       gsettings org.gnome.desktop.interface as XSETTINGS. The theme name MUST be
#       a directory name under ~/.themes. "Adwaita:dark" is GTK_THEME-env syntax,
#       via XSETTINGS it resolves to nothing and GTK falls back to LIGHT Adwaita.
#       gsettings live in dconf; .config/qtile/autostart_x11.sh re-asserts them.
#   GTK4/libadwaita (flatpaks)  : .config/gtk-4.0/gtk.css (@define-color overrides),
#       exposed to sandboxes via the flatpak overrides below.
#   Qt5 native (copyq, polkit)  : qt5ct, QT_QPA_PLATFORMTHEME=qt5ct in bin/starting-qtile.sh
#   Qt on org.kde.Platform      : .config/kdeglobals + QT_QPA_PLATFORMTHEME=kde override
#   qtile bar / dunst / rofi / kitty : stowed configs, same palette.
dnf -y install gtk-murrine-engine gtk2-engines qt5ct papirus-icon-theme   # murrine + clearlooks: GTK2 half of the theme (EPEL)

ROSE_GTK_VER="v2.2.0"; ROSE_CUR_VER="v1.1.0"
sudo -iu "$TARGET_USER" env ROSE_GTK_VER="$ROSE_GTK_VER" ROSE_CUR_VER="$ROSE_CUR_VER" bash -e <<'THEME'
  mkdir -p ~/.themes ~/.icons
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/gtk3.tar.gz"    "https://github.com/rose-pine/gtk/releases/download/$ROSE_GTK_VER/gtk3.tar.gz"
  curl -fsSL -o "$tmp/cursors.tar.xz" "https://github.com/rose-pine/cursors/releases/download/$ROSE_CUR_VER/BreezeX-RosePine-Linux.tar.xz"
  tar xzf "$tmp/gtk3.tar.gz" -C "$tmp" 2>/dev/null
  for t in rose-pine-gtk rose-pine-moon-gtk; do
    rm -rf ~/.themes/$t && cp -r "$tmp/gtk3/$t" ~/.themes/
    # Upstream ships a mis-generated LIGHT gtk-dark.css. With
    # gtk-application-prefer-dark-theme=1 GTK loads exactly that file, so make
    # the "dark variant" the real (already dark) theme.
    for v in gtk-3.0 gtk-3.20; do cp ~/.themes/$t/$v/gtk.css ~/.themes/$t/$v/gtk-dark.css; done
  done
  tar xJf "$tmp/cursors.tar.xz" -C ~/.icons 2>/dev/null
  printf '[Icon Theme]\nName=Default\nComment=Default Cursor Theme\nInherits=BreezeX-RosePine-Linux\n' > ~/.icons/default/index.theme
  rm -rf "$tmp"

  # authoritative GTK settings (XSETTINGS source); mirrored in .config/gtk-3.0/settings.ini
  gsettings set org.gnome.desktop.interface gtk-theme    'rose-pine-gtk'
  gsettings set org.gnome.desktop.interface icon-theme   'Papirus-Dark'
  gsettings set org.gnome.desktop.interface cursor-theme 'BreezeX-RosePine-Linux'
  gsettings set org.gnome.desktop.interface cursor-size  24
  gsettings set org.gnome.desktop.interface font-name    'Cantarell 11'
  gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono Nerd Font 10'

  # flatpak: let sandboxes see the theme, the gtk-4.0/gtk.css overrides and
  # kdeglobals; route KDE-runtime Qt apps through the KDE platform theme.
  # GTK_THEME must NOT be forced: it disables libadwaita's own styling.
  flatpak override --user --unset-env=GTK_THEME
  flatpak override --user --env=QT_QPA_PLATFORMTHEME=kde \
    --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro \
    --filesystem=xdg-config/kdeglobals:ro --filesystem=~/.themes:ro --filesystem=~/.icons:ro

  # Obsidian (Electron) paints its own UI and ignores GTK entirely: install the
  # official Rosé Pine theme into every known vault and select it. Vault
  # registry only exists after Obsidian's first run, so this is a no-op on a
  # fresh box until then - safe to re-run.
  OBS_REG=~/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json
  if [ -f "$OBS_REG" ]; then
    python3 -c 'import json,sys; [print(v["path"]) for v in json.load(open(sys.argv[1]))["vaults"].values()]' "$OBS_REG" |
    while read -r vault; do
      [ -d "$vault/.obsidian" ] || continue
      mkdir -p "$vault/.obsidian/themes/Rose Pine"
      curl -fsSL -o "$vault/.obsidian/themes/Rose Pine/manifest.json" https://raw.githubusercontent.com/rose-pine/obsidian/main/manifest.json
      curl -fsSL -o "$vault/.obsidian/themes/Rose Pine/theme.css"     https://raw.githubusercontent.com/rose-pine/obsidian/main/theme.css
      cat > "$vault/.obsidian/appearance.json" <<'APPEARANCE'
{
  "theme": "obsidian",
  "cssTheme": "Rose Pine",
  "interfaceFontFamily": "Cantarell",
  "textFontFamily": "Cantarell",
  "monospaceFontFamily": "JetBrains Mono Nerd Font"
}
APPEARANCE
    done
  fi

  # Brave: official Rosé Pine theme from the Chrome Web Store, via Chromium's
  # "External Extensions" mechanism (picked up on next Brave start, no click).
  mkdir -p ~/.config/BraveSoftware/Brave-Browser/"External Extensions"
  printf '{\n  "external_update_url": "https://clients2.google.com/service/update2/crx"\n}\n' \
    > ~/.config/BraveSoftware/Brave-Browser/"External Extensions"/noimedcjdohhokijigpfcbjcfcaaahej.json
  # Fallback if the store is ever blocked: brave://extensions -> Load unpacked -> ~/.config/rose-pine-chrome

  # LibreWolf: addons.mozilla.org is blocked by the corporate filter, so the
  # theme is a locally built static-theme XPI (.config/rose-pine-firefox, colours
  # from the official Firefox Color preset) sideloaded into every profile.
  for ini in ~/.librewolf/profiles.ini ~/.var/app/io.gitlab.librewolf-community/.librewolf/profiles.ini; do
    [ -f "$ini" ] || continue
    root=$(dirname "$ini")
    grep -E '^Path=' "$ini" | cut -d= -f2 | while read -r rel; do
      prof="$root/$rel"; [ -d "$prof" ] || continue
      mkdir -p "$prof/extensions"
      cp ~/.config/rose-pine-firefox/rose-pine@rosepinetheme.com.xpi "$prof/extensions/"
      grep -q 'rose-pine@rosepinetheme.com' "$prof/user.js" 2>/dev/null && continue
      cat >> "$prof/user.js" <<'USERJS'

// ── Rosé Pine static theme, sideloaded from ~/.dotfiles/.config/rose-pine-firefox ──
user_pref("xpinstall.signatures.required", false);       // locally built XPI is unsigned
user_pref("extensions.sideloadScopes", 1);                // Firefox >=74 ignores profile extensions/ without this
user_pref("extensions.autoDisableScopes", 14);            // ...and auto-enable what it finds there
user_pref("extensions.activeThemeID", "rose-pine@rosepinetheme.com");
user_pref("layout.css.prefers-color-scheme.content-override", 0);  // sites get prefers-color-scheme: dark
USERJS
    done
  done
  # NOTE: a freshly sideloaded theme registers but is not switched on by
  # activeThemeID alone; enable it once under about:addons -> Themes on the
  # first run after this (or flip active/userDisabled in extensions.json).
THEME

### 10. Default applications
mkdir -p /home/$TARGET_USER/.config
# Flatpak VSCodium as default editor (for $TARGET_USER)
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default codium.desktop text/plain
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default codium.desktop text/x-python
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default codium.desktop text/x-shellscript
# Flatpak Brave as default browser (for $TARGET_USER)
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-settings set default-web-browser brave-browser.desktop
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default brave-browser.desktop x-scheme-handler/http
sudo -u "$TARGET_USER" XDG_CONFIG_HOME="/home/$TARGET_USER/.config" xdg-mime default brave-browser.desktop x-scheme-handler/https
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
