#!/usr/bin/env bash
#
# install.sh ─ one-shot bootstrap for a fresh **Rocky / RHEL 9** workstation
# • adds CRB + EPEL repos
# • installs runtime services, utilities and apps needed for a WM session in x11
# • builds **picom** from source (yshui fork, release build)
# • grabs various apps from Flathub
# • grabs xss-lock and variety from source
# • grabs fonts from source
# • **Qtile X11** in a per-user virtual-env + desktop file
#
# Run as root: sudo ./install.sh
set -euo pipefail

### 0. Sanity
if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

### 0. Variables and setup ─────────────────────────────────────────────────────────────
TARGET_USER="$(logname)"                 # primary human user
QTILE_VENV="/home/$TARGET_USER/.local/venvs/qtile"

chmod +x ./.config/qtile/lock_with_random_bg.sh
chmod +x ./.config/qtile/autostart.sh

### 1. Repos ────────────────────────────────────────────────────────────────
dnf -y install epel-release epel-next-release flatpak git stow
dnf -y config-manager --set-enabled crb
dnf install rpmfusion-free-release
dnf install --nogpgcheck https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm

dnf groupupdate corednf groupupdate multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

dnf groupupdate multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf groupupdate sound-and-video

dnf install snapd
systemctl enable --now snapd.socket
ln -s /var/lib/snapd/snap /snap
snap refresh
snap install core
snap install direnv
dnf clean all
dnf makecache
dnf update

# Add Flathub remote for user 1000 (adjust if needed)
sudo -iu "$(logname)" flatpak remote-add --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

### 2. QTile X11 ──────────────────────────────────────────────────────────────
dnf -y install \
  python3 python3-devel python3.12-devel python3-gobject python3-pip libffi-devel cairo cairo-devel \
  pango pango-devel gobject-introspection-devel libXScrnSaver-devel spice-vdagent \
  libxkbcommon libxkbcommon-devel xcb-util-keysyms-devel xcb-util-wm-devel \
  xcb-util-devel libXcursor-devel libXinerama-devel python3-pyopengl \
  jetbrains-mono-nl-fonts fontawesome-fonts open-vm-tools open-vm-tools-desktop

# create venv & install qtile as the target user
sudo -iu "$TARGET_USER" bash <<EOF
set -e
python3 -m venv "$QTILE_VENV"
source "$QTILE_VENV/bin/activate"
pip install --upgrade pip
pip install qtile qtile-extras mypy typeshed-client typing_extensions pulsectl dbus-next psutil
pip install --upgrade python-dateutil dbus-fast
# generate default config (writes to ~/.config/qtile/config.py)
qtile start --write-default-config
EOF

# system-wide desktop session entry
cat >/usr/share/xsessions/qtile.desktop <<'EOF'
[Desktop Entry]
Name=Qtile
Comment=Qtile Tiling Window Manager (Python, X11)
Exec=/home/%u/.local/venvs/qtile/bin/qtile start
Type=Application
Keywords=wm;tiling
EOF

### 3. Runtime packages ─────────────────────────────────────────────────────
dnf -y install \
  btop \
  gnome-keyring-pam \
  polkit-gnome \
  copyq \
  network-manager-applet \
  blueman \
  udiskie \
  redshift \
  i3lock \
  pulseaudio-utils \
  pavucontrol \ bluez \
  bluez-libs \
  python3-dbus \
  acpid \
  kitty

# optional compositor placeholder until picom builds
dnf -y install xcompmgr

### 4. Flatpaks apps ─────────────────────────────────────────────────────

sudo -iu "$TARGET_USER" flatpak install -y --noninteractive flathub \
  org.flameshot.Flameshot \          
  org.librewolf.Librewolf \          
  com.brave.Browser \                
  com.vscodium.codium \              
  com.github.tchx84.Flatseal  

### 5. other tools from source ───────────────────────────────────────────────
### 5.1 dunst from source ───────────────────────────────────────────────
git clone https://github.com/dunst-project/dunst.git --depth 1
cd dunst

# configure a Release build that installs into /usr/local
meson setup build --prefix=/usr/local --buildtype=release
ninja -C build                     # compile
sudo ninja -C build install        # install binaries + desktop files

### 5.2 xss-lock from source ───────────────────────────────────────────────
sudo dnf install gcc make cmake            \
     libX11-devel libXScrnSaver-devel      \
     xorg-x11-proto-devel                  \
     libxcb-devel libxkbcommon-devel

# 1) grab source
git clone https://bitbucket.org/raymonad/xss-lock
cd xss-lock

# 2) configure & compile
mkdir build && cd build
cmake .  -DCMAKE_INSTALL_PREFIX=/usr   # generates build.ninja / Makefiles
make -j$(nproc)

# 3) install system-wide
sudo make install

cd ..

### 5.3 variety from source ───────────────────────────────────────────────

git clone https://github.com/varietywalls/variety.git
cd variety

dnf config-manager --set-enabled epel-testing && dnf install python3-distutils-extra python3-pillow imlib2-devel libcurl-devel libXt-devel
dnf install python3-beautifulsoup4 python3-feedparser python3-requests python3-lxml python3-configobj python3-httplib2

python3 setup.py install

### variety dependencies (feh) ───────────────────────────────────────────────
cd /usr/local/src
git clone https://github.com/derf/feh.git
cd feh & make & make install app=1

### 5.4 rofi from source ───────────────────────────────────────────────
dnf install libxkbcommon-x11-devel xcb-util-cursor-devel
cd /usr/local/src
git clone --depth=1 --branch 1.7.3 https://github.com/davatorium/rofi.git
cd rofi
meson setup build --prefix=/usr/local --buildtype=release
ninja -C build
ninja -C build install

### 5.5 fonts from source ────────────────────────────────────────────────────

tmp=$(mktemp -d)
curl -L https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o "$tmp/jbm.zip"
mkdir -p /usr/local/share/fonts/JetBrainsMonoNF
unzip -u "$tmp/jbm.zip" -d /usr/local/share/fonts/JetBrainsMonoNF
fc-cache -fv
rm -r "$tmp"

fc-cache -fv

mkdir -p ~/.icons
curl -L https://github.com/dracula/gtk/releases/latest/download/Dracula-cursors.tar.xz \
  | tar -xJf - -C ~/.icons


### 5.6 misc utils from source ───────────────────────────────────────────────

curl -sfL https://direnv.net/install.sh | bash

cd cd /usr/local/src
git clone https://github.com/lxde/lxappearance.git
cd lxappearance
./autogen.sh --prefix=/usr/local
./configure --prefix=/usr/local
make & make install

### 6. Build-time deps for picom ─────────────────────────────────────────────
### 1. Dependencies ---------------------------------------------------
dnf -y groupinstall 'Development Tools'
dnf -y install \
  dbus-devel libconfig-devel libev-devel libX11-devel libxcb-devel \
  mesa-libGL-devel mesa-libEGL-devel libepoxy-devel meson ninja-build \
  pcre2-devel pixman-devel uthash-devel xcb-util-image-devel \
  xcb-util-renderutil-devel xcb-util-devel xorg-x11-proto-devel asciidoctor

### 2. Clone & build picom ---------------------------------------------------
workdir="/usr/local/src/picom"
git clone --depth=1 https://github.com/yshui/picom.git "$workdir"
cd "$workdir"
meson setup --buildtype=release build
ninja -C build
ninja -C build install      # installs under /usr/local/bin by default

### 3. Clean-up placeholder compositor
dnf -y remove xcompmgr || true

### 4. Clone wallpapers ---------------------------------------------------

cd & cd Pictures/ & git clone https://github.com/f-klement/wallpapers.git

echo "Migration complete! \n Use stow . to symlink the dotfiles once you are settled in"

### config Wallpaper
variety &

