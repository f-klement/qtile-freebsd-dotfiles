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
[[ -L /snap ]] || ln -s /var/lib/snapd/snap /snap && sleep 10
snap install core direnv

sudo -iu "$TARGET_USER" flatpak remote-add --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

### 3. Qtile (Wayland dev libs + XWayland fallback) ─────────────────────────────
dnf install -y \
  python3 python3.12 python3-devel polkit-kde-agent-1 python3-pip python3-gobject \
  libffi-devel cairo cairo-devel pango pango-devel gobject-introspection-devel \
  wayland-devel wayland-protocols-devel libinput-devel libseat-devel \
  libxkbcommon-devel spice-vdagent python3-cffi wlroots \
  fontawesome-fonts open-vm-tools open-vm-tools-desktop \
  python3-dbus acpid python3.12-devel python-xkbcommon \
  xorg-x11-server-Xwayland    # for XWayland apps

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

cat >/usr/share/wayland-sessions/qtile.desktop <<EOF
[Desktop Entry]
Name=Qtile (Wayland)
Comment=Qtile Tiling Window Manager (via XWayland + native Wayland libs)
Exec=/home/$TARGET_USER/.local/venvs/qtile/bin/qtile start -b wayland
Type=Application
Keywords=wm;tiling;wayland
EOF

### 4. Runtime packages & Wayland utilities ────────────────────────────────────
dnf install -y \
  btop gnome-keyring network-manager-applet \
  redshift pulseaudio-utils pavucontrol copyq\
  bluez bluez-libs wlr-randr kitty vlc blueman swaybg feh\
  swaylock swayidle wofi wl-clipboard wayland-utils wlr-randr
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



# Wallpapers
[[ -d /home/$TARGET_USER/Pictures/wallpapers ]] || \
  git clone https://github.com/f-klement/wallpapers.git /home/$TARGET_USER/Pictures/wallpapers

### 7. Node, Bun and uv for Python
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
nvm install node
curl -fsSL https://bun.com/install | bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

curl -LsSf https://astral.sh/uv/install.sh | sh
echo 'eval "$(uv generate-shell-completion zsh)"' >> ~/.zshrc
echo 'eval "$(uvx --generate-shell-completion zsh)"' >> ~/.zshrc


### 8. clis & tuis
# fzf
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
# ripgrep
# rust for rg
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

#rg
git clone https://github.com/BurntSushi/ripgrep
cd ripgrep
cargo build --release
mv ./target/release/rg /usr/local/bin/

#docker & lazydocker
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install docker-ce docker-ce-cli containerd.io docker-compose-plugin.x86_64
systemctl start docker
systemctl enable docker
usermod -aG docker "$TARGET_USER"

curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash  

# homebrew (snap and flatpak don't always cover relevant dev dependancies, eg. a new gcc compiler)
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"
echo >> /home/admin/.zshrc
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"' >> /home/admin/.zshrc
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
/home/linuxbrew/.linuxbrew/bin/brew install gcc

### 9. Default applications
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

echo "✔ Fedora Wayland + Qtile bootstrap complete, use GNU stow and enjoy!"
