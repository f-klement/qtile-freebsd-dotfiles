#!/usr/bin/env sh
#
# x11_bootstrap.sh ─ one-shot bootstrap for a fresh **FreeBSD 14+** workstation:
# Xorg, qtile-x11, picom, the WM utilities, and the everyday applications, all
# from the native `pkg` repository.
#
# This is the FreeBSD port of a Rocky/RHEL 8 provisioner. On EL8 most of this
# stack had to be built from source and pulled from third-party RPM repos
# (EPEL, RPMFusion, the VSCodium/Brave repos), plus a large section of
# GNOME/systemd/kernel hardening. On FreeBSD nearly everything below is a single
# packaged port, so the source builders, the extra repos, and the Linux-only
# kernel/session tuning are all gone.
#
# What was DROPPED from the EL8 version and why:
#   * dnf/EPEL/RPMFusion/CRB/snapd/flatpak/vscodium.repo/brave.repo
#       -> FreeBSD has one first-class package set (pkg); no third-party repos.
#   * from-source builds of i3lock/dunst/xss-lock/feh/rofi/picom/lxappearance
#       -> all packaged in pkg.
#   * Homebrew (linuxbrew), bleachbit, AppImageLauncher, lazydocker, Bruno
#       -> no FreeBSD support / no clean FreeBSD path.
#   (bun IS kept: it ships native FreeBSD binaries now -- installed in section 6.)
#   * rust
#       -> only existed to compile ripgrep on EL8; ripgrep is prebuilt here.
#   * podman + its rootless overlay/systemd/subuid/cgroup plumbing
#       -> Linux container stack; FreeBSD needs ZFS/jail/pf setup. Dropped
#          entirely -- use a Linux jail/VM if you need containers.
#   * gnome-session trimming, tracker masking, vm.dirty_bytes sysctl, zswap +
#     grubby kernel args, Brave GPU flags
#       -> all Linux/GNOME/kernel specific. qtile is launched directly here, and
#          FreeBSD's VM/swap needs no such tuning.
#   * open-vm-tools / spice-vdagent
#       -> this guest is KVM/virtio (vtnet0), so it uses qemu-guest-agent.
#
set -eu

### 0. Sanity check ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

if [ "$(uname -s)" != "FreeBSD" ]; then
  echo "This bootstrap targets FreeBSD. For the RHEL/EL version see the git history." >&2
  exit 1
fi

### 0. Variables & helpers ─────────────────────────────────────────────────────
TARGET_USER="$(logname)"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)"
: "${TARGET_HOME:=/home/$TARGET_USER}"
# This repo (the dir this script lives in) is the stow package deployed to $HOME.
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/usr/local/sbin:/usr/local/bin:$PATH"
export ASSUME_ALWAYS_YES=yes          # pkg: never prompt

echo "platform: $(freebsd-version) on $(sysctl -n kern.vm_guest 2>/dev/null || echo bare-metal)"

# Run a command as the unprivileged target user, with a login environment.
as_user() { su -l "$TARGET_USER" -c "$*"; }

# pkg install is idempotent (installed packages are skipped), so there is no
# need for a "skip_if_installed" / build-from-source wrapper. Everything below is
# one pkg transaction per section.
pkgi() { pkg install -y "$@"; }

### 1. Bootstrap pkg & base CLI ─────────────────────────────────────────────────
# Fetch the pkg bootstrap on a truly fresh install, then refresh the catalogue.
ASSUME_ALWAYS_YES=yes pkg bootstrap || true
pkg update

pkgi \
  git curl wget unzip stow bash zsh \
  xdg-utils dbus

# dbus is needed by most GTK/Qt apps, gnome-keyring, and notifications.
sysrc dbus_enable=YES
service dbus start 2>/dev/null || true

### 2. Xorg + qtile (X11) ───────────────────────────────────────────────────────
# qtile itself is packaged (py312-qtile); it pulls in python 3.12, cairo, pango,
# pangocffi/cairocffi, xcffib and the xcb libraries as dependencies, so no
# separate -devel/build list is needed.
pkgi \
  xorg xinit \
  py312-qtile py312-pip py312-psutil \
  polkit-gnome \
  sddm \
  qemu-guest-agent

# qtile-extras is NOT in pkg. Install it into the target user's site so the
# pkg-provided /usr/local/bin/qtile (running under the system python 3.12) picks
# it up from ~/.local/lib/python3.12/site-packages. The config's PulseVolume
# dependency (pulsectl_asyncio) is intentionally NOT installed: config.py reads
# the volume through the base-system mixer(8) instead.
as_user "python3.12 -m pip install --user --break-system-packages --upgrade pip qtile-extras"

# Qtile session entry for the SDDM greeter. Exec points at the shared launcher
# (/usr/local/bin/qtile-session, written in section 9) so the toolkit env is set
# whether the session starts from SDDM or from `startx`.
mkdir -p /usr/local/share/xsessions
cat >/usr/local/share/xsessions/qtile.desktop <<'DESKTOP'
[Desktop Entry]
Name=Qtile
Comment=Qtile Tiling Window Manager (Python 3.12, X11)
Exec=/usr/local/bin/qtile-session
Type=Application
Keywords=wm;tiling
DESKTOP

# KVM/virtio guest agent (replaces open-vm-tools on this hypervisor).
sysrc qemu_guest_agent_enable=YES
service qemu-guest-agent start 2>/dev/null || true

# German keyboard layout at the X-server level, so it applies to BOTH the SDDM
# greeter and the qtile session (no gsd-keyboard here to set it). The qtile
# autostart also runs `setxkbmap de` as a belt-and-suspenders.
mkdir -p /usr/local/etc/X11/xorg.conf.d
cat >/usr/local/etc/X11/xorg.conf.d/10-keyboard.conf <<'KBD'
Section "InputClass"
    Identifier  "keyboard-all"
    MatchIsKeyboard "on"
    Option      "XkbLayout" "de"
    Option      "XkbModel"  "pc105"
EndSection
KBD

### 2.5 Accelerated video (virtio-gpu KMS) ──────────────────────────────────────
# IMPORTANT: this needs the VM's display device to be **virtio-gpu**, NOT QXL or
# plain std/bochs VGA. QXL/std have no FreeBSD KMS driver, so Xorg falls back to
# the unaccelerated `scfb` framebuffer -> sluggish scrolling and screen tearing.
#
#   QEMU:      -device virtio-gpu-pci        (2D KMS; enough to be tear-free)
#              -device virtio-vga-gl  + host virglrenderer  (adds 3D/GL)
#   libvirt:   set the <video><model type="virtio"/> (Virtio, optionally 3D).
#
# Guest side: install the DRM KMS module + Mesa, load virtio_gpu at boot. Once a
# /dev/dri/card0 exists, Xorg auto-selects the accelerated `modesetting` driver.
pkgi drm-kmod mesa-dri mesa-libs libglvnd
# Load virtio_gpu from loader.conf (early, at the loader stage) rather than rc's
# kld_list -- KMS drivers are more reliable loaded before the kernel probes the
# console, and this is what actually creates /dev/dri.
sysrc -f /boot/loader.conf virtio_gpu_load=YES
sysrc kld_list-="virtio_gpu" 2>/dev/null || true   # drop the less-reliable rc path if set

# Faster boot: skip the beastie menu and its 10s countdown (the FreeBSD analogue
# of a GRUB timeout). It boots straight to multi-user; SDDM then handles login.
sysrc -f /boot/loader.conf autoboot_delay=1 beastie_disable=YES

# Persist a 16:10 preferred mode for the greeter (session-level fallback lives in
# autostart_x11.sh). Harmless under scfb; applies once modesetting is active.
cat >/usr/local/etc/X11/xorg.conf.d/20-virtio-mode.conf <<'MODE'
Section "Device"
    Identifier "virtio-gpu"
    Driver     "modesetting"
EndSection
Section "Monitor"
    Identifier    "Virtual-1"
    Option        "PreferredMode" "1920x1200"
EndSection
MODE

# The scfb pin, if present, must be removed so modesetting can take over -- but
# ONLY once real DRM hardware is available, otherwise X has no driver at all.
if [ -e /dev/dri/card0 ]; then
  rm -f /usr/local/etc/X11/xorg.conf.d/driver-scfb.conf
  echo "video: /dev/dri/card0 present -> using accelerated modesetting"
else
  echo "video: no /dev/dri yet. It appears after a reboot (loader loads"
  echo "       virtio_gpu). This run leaves the scfb pin in place; the NEXT"
  echo "       bootstrap run (post-reboot) removes it automatically."
fi

### 3. WM utilities & runtime packages ─────────────────────────────────────────
# All packaged in pkg.
pkgi \
  kitty rofi dunst picom feh xss-lock i3lock-color copyq \
  pulseaudio pavucontrol \
  redshift btop gnome-keyring py312-ranger \
  qt5ct qt6ct adwaita-qt5 gsettings-desktop-schemas \
  vlc \
  xrandr xset xsetroot xprop \
  flameshot scrot ImageMagick7 xclip

# Media codecs. FreeBSD needs NO 'audio' group -- /dev/dsp* and /dev/mixer* are
# world-accessible (0666), and PulseAudio autospawns per user session, so sound
# works with no membership or service to enable. ffmpeg (the codec library) comes
# in as a vlc dependency; the GStreamer plugin sets give GTK apps, thumbnailers
# and browser fallbacks broad format coverage (h264/aac/mp3/webm/...).
pkgi \
  ffmpeg \
  gstreamer1-plugins gstreamer1-plugins-good \
  gstreamer1-plugins-bad gstreamer1-plugins-ugly gstreamer1-libav

### 4. GUI applications ─────────────────────────────────────────────────────────
# LibreWolf is the browser (Brave has no FreeBSD port); nautilus is the file
# manager. Obsidian and KeePassXC were dropped from this setup.
pkgi \
  librewolf \
  nautilus

### 5. Fonts, icons & GTK theme engines ─────────────────────────────────────────
# nerd-fonts provides "JetBrainsMono Nerd Font" (the qtile bar / kitty font);
# papirus-icon-theme + the GTK2 murrine/clearlooks engines back the Rosé Pine
# GTK theme downloaded in section 8.
pkgi \
  nerd-fonts papirus-icon-theme dejavu \
  gtk-murrine-engine gtk-engines2
fc-cache -f >/dev/null 2>&1 || true

### 6. Developer tooling ────────────────────────────────────────────────────────
# Mostly packaged directly by pkg. Dropped from the EL8 version, with reasons:
#   rust      - only existed on EL8 to compile ripgrep, which is prebuilt here.
#   podman    - needs FreeBSD-specific ZFS/jail/pf setup; not runnable out of the
#               box (use a Linux jail/VM if you need containers).
#   lazydocker, Homebrew, Bruno - no FreeBSD port / no clean FreeBSD path.
pkgi \
  node npm \
  fzf ripgrep fd-find direnv gdu fastfetch \
  uv

# pnpm is the node package manager (not in pkg; provided by node's corepack). It
# has a native rolling minimum-release-age cooldown, configured in ~/.npmrc
# (stowed: minimum-release-age=4320 -> 3 days). uv's cooldown is the global
# UV_EXCLUDE_NEWER exported from ~/.zshrc. corepack writes the pnpm shim into
# /usr/local/bin; enable it as root, then fetch the runtime as the user.
corepack enable pnpm 2>/dev/null || npm install -g pnpm
as_user "corepack prepare pnpm@latest --activate" 2>/dev/null || true

# Bun. Contrary to older lore, Bun ships NATIVE FreeBSD binaries now (1.4+,
# bun-freebsd-x64/aarch64). The npm package is an installer shim whose postinstall
# fetches that binary; npm 12 gates install scripts, so allow it explicitly and
# prime the download here rather than lazily on first run. NB: `bun install` has
# no minimum-release-age gate -- the supply-chain cooldown lives in pnpm/uv.
npm install -g --allow-scripts=bun bun 2>/dev/null || npm install -g bun
bun --revision >/dev/null 2>&1 || true   # trigger the native-binary download if still deferred

### 7. Wallpapers ───────────────────────────────────────────────────────────────
if [ ! -d "$TARGET_HOME/Pictures/wallpapers" ]; then
  as_user "git clone https://github.com/f-klement/wallpapers.git '$TARGET_HOME/Pictures/wallpapers'" || true
fi

### 8. Theming ─ Rosé Pine, dark, across toolkits ──────────────────────────────
# How theming reaches each toolkit under qtile:
#   GTK2/3 + Chromium/Electron : gsettings org.gnome.desktop.interface, broadcast
#       as XSETTINGS by gsd-xsettings if present; .config/qtile/autostart_x11.sh
#       re-asserts them every login. The theme name MUST be a directory under
#       ~/.themes ("Adwaita:dark" is GTK_THEME-env syntax and resolves to nothing
#       via XSETTINGS).
#   Qt5 native (copyq, polkit)  : qt5ct + QT_QPA_PLATFORMTHEME=qt5ct.
#   qtile bar / dunst / rofi / kitty : stowed configs, same palette.
#
# rose-pine-gtk and the BreezeX-RosePine cursor are not packaged, so pull the
# release tarballs. The flatpak/Obsidian/Brave theme plumbing is gone; LibreWolf
# theming stays.
ROSE_GTK_VER="v2.2.0"; ROSE_CUR_VER="v1.1.0"
as_user "env ROSE_GTK_VER='$ROSE_GTK_VER' ROSE_CUR_VER='$ROSE_CUR_VER' sh -e" <<'THEME'
  mkdir -p ~/.themes ~/.icons ~/.icons/default
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/gtk3.tar.gz"    "https://github.com/rose-pine/gtk/releases/download/$ROSE_GTK_VER/gtk3.tar.gz" || exit 0
  curl -fsSL -o "$tmp/cursors.tar.xz" "https://github.com/rose-pine/cursors/releases/download/$ROSE_CUR_VER/BreezeX-RosePine-Linux.tar.xz" || true
  tar xzf "$tmp/gtk3.tar.gz" -C "$tmp" 2>/dev/null || true
  for t in rose-pine-gtk rose-pine-moon-gtk; do
    [ -d "$tmp/gtk3/$t" ] || continue
    rm -rf ~/.themes/$t && cp -r "$tmp/gtk3/$t" ~/.themes/
    # Upstream ships a mis-generated LIGHT gtk-dark.css; with
    # gtk-application-prefer-dark-theme=1 GTK loads exactly that, so make the
    # "dark variant" the real (already dark) theme.
    for v in gtk-3.0 gtk-3.20; do
      [ -f ~/.themes/$t/$v/gtk.css ] && cp ~/.themes/$t/$v/gtk.css ~/.themes/$t/$v/gtk-dark.css
    done
  done
  [ -f "$tmp/cursors.tar.xz" ] && tar xJf "$tmp/cursors.tar.xz" -C ~/.icons 2>/dev/null || true
  printf '[Icon Theme]\nName=Default\nComment=Default Cursor Theme\nInherits=BreezeX-RosePine-Linux\n' > ~/.icons/default/index.theme
  rm -rf "$tmp"

  # authoritative GTK settings (XSETTINGS source); mirrored in .config/gtk-3.0/settings.ini
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface gtk-theme    'rose-pine-gtk'   || true
    gsettings set org.gnome.desktop.interface icon-theme   'Papirus-Dark'    || true
    gsettings set org.gnome.desktop.interface cursor-theme 'BreezeX-RosePine-Linux' || true
    gsettings set org.gnome.desktop.interface cursor-size  24                || true
    gsettings set org.gnome.desktop.interface font-name    'Cantarell 11'    || true
    gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono Nerd Font 10' || true
  fi

  # LibreWolf: sideload the locally built Rosé Pine static-theme XPI into every
  # profile (addons.mozilla.org may be filtered). No flatpak path on FreeBSD.
  ini=~/.librewolf/profiles.ini
  if [ -f "$ini" ] && [ -f ~/.config/rose-pine-firefox/rose-pine@rosepinetheme.com.xpi ]; then
    root=$(dirname "$ini")
    grep -E '^Path=' "$ini" | cut -d= -f2 | while read -r rel; do
      prof="$root/$rel"; [ -d "$prof" ] || continue
      mkdir -p "$prof/extensions"
      cp ~/.config/rose-pine-firefox/rose-pine@rosepinetheme.com.xpi "$prof/extensions/"
      grep -q 'rose-pine@rosepinetheme.com' "$prof/user.js" 2>/dev/null && continue
      cat >> "$prof/user.js" <<'USERJS'

// ── Rosé Pine static theme, sideloaded from ~/.dotfiles/.config/rose-pine-firefox ──
user_pref("xpinstall.signatures.required", false);
user_pref("extensions.sideloadScopes", 1);
user_pref("extensions.autoDisableScopes", 14);
user_pref("extensions.activeThemeID", "rose-pine@rosepinetheme.com");
user_pref("layout.css.prefers-color-scheme.content-override", 0);
USERJS
    done
  fi
THEME

### 9. Deploy dotfiles ─ normalize, stow, shell ────────────────────────────────
# Everything above installed software; this section puts the actual configuration
# in place so a fresh box is fully set up in one run.

# 9.1 Normalize any stale absolute home paths. Some stowed configs were authored
# under a different account (/home/florian -> qt5ct color path, gtkrc include,
# .zshrc). Rewrite them to the real home so theming + shell resolve. Idempotent:
# a second run finds nothing to change.
find "$DOTFILES_DIR" -type f -not -path '*/.git/*' 2>/dev/null | while read -r f; do
  if grep -Iq "/home/florian" "$f" 2>/dev/null; then
    sed -i '' "s#/home/florian#$TARGET_HOME#g" "$f"
  fi
done

# 9.2 Login shell = zsh, with oh-my-zsh (the stowed .zshrc sources it). --keep-zshrc
# so the installer does NOT drop its own .zshrc and conflict with stow.
if [ ! -d "$TARGET_HOME/.oh-my-zsh" ]; then
  as_user 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc' \
    || echo "note: oh-my-zsh install skipped (network?)"
fi
pw usermod "$TARGET_USER" -s /usr/local/bin/zsh 2>/dev/null || true

# 9.3 Symlink all configs into $HOME with GNU stow. The repo root is the package;
# stow's default target is its parent ($HOME). .stow-local-ignore already excludes
# the bootstrap, README, archive, __pycache__, etc. --restow makes it idempotent.
as_user "cd '$DOTFILES_DIR' && stow --restow --target='$TARGET_HOME' ." \
  || echo "WARNING: stow reported conflicts - resolve them, then re-run 'stow --restow .'"

# 9.4 Session launcher (the old bin/starting-qtile.sh is gone). This is THE place
# for toolkit env, since everything qtile spawns inherits it. Shared by BOTH
# launch paths: SDDM runs it via qtile.desktop's Exec, and `startx` runs it via
# ~/.xinitrc. One launcher => identical environment either way.
cat > /usr/local/bin/qtile-session <<'LAUNCH'
#!/bin/sh
export XDG_CURRENT_DESKTOP=Qtile
export XDG_SESSION_DESKTOP=qtile
# Qt theming via qt5ct/qt6ct (Rosé Pine palette). QT_QPA_PLATFORMTHEME can only
# name one plugin; qt5ct covers the Qt5 apps here (copyq, vlc, ...). For Qt6 apps
# switch this to qt6ct (config is installed at ~/.config/qt6ct).
export QT_QPA_PLATFORMTHEME=qt5ct
export XCURSOR_THEME=BreezeX-RosePine-Linux
export XCURSOR_SIZE=24
# keep qtile's compiled config.py out of the stowed (symlinked) config dir
export PYTHONPYCACHEPREFIX="$HOME/.cache/python-pycache"
# secrets / ssh agent
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg 2>/dev/null)"
  export SSH_AUTH_SOCK GNOME_KEYRING_CONTROL
fi
# propagate the above to D-Bus-activated apps
command -v dbus-update-activation-environment >/dev/null 2>&1 && \
  dbus-update-activation-environment --all 2>/dev/null || true
exec qtile start
LAUNCH
chmod +x /usr/local/bin/qtile-session

# startx fallback (no display manager): ~/.xinitrc runs the same launcher.
printf '#!/bin/sh\nexec /usr/local/bin/qtile-session\n' > "$TARGET_HOME/.xinitrc"
chmod +x "$TARGET_HOME/.xinitrc"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"

# SDDM is the display manager (a login greeter, NOT a session manager -- it
# launches qtile directly via qtile.desktop, no gnome-session in between). It
# lists the Qtile session from /usr/local/share/xsessions/qtile.desktop above.
sysrc sddm_enable=YES
# /dev/dri access for the logged-in user's GL apps under the accelerated driver.
pw groupmod video -m "$TARGET_USER" 2>/dev/null || true

# 9.5 Rosé Pine SDDM theme. Self-contained (no external repo): a compact QtQuick
# greeter with the Rosé Pine palette. If a future SDDM/Qt rev dislikes the QML it
# falls back to the default theme -- login still works, just unstyled.
SDDM_THEME=/usr/local/share/sddm/themes/rose-pine
mkdir -p "$SDDM_THEME"
cat >"$SDDM_THEME/metadata.desktop" <<'META'
[SDDM Theme]
Name=rose-pine
Description=Rosé Pine
Author=dotfiles
Type=sddm-theme
Version=1.0
MainScript=Main.qml
ConfigFile=theme.conf
META
cat >"$SDDM_THEME/theme.conf" <<'TCONF'
[General]
background=
TCONF
cat >"$SDDM_THEME/Main.qml" <<'QML'
import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    anchors.fill: parent
    color: "#191724"                 // rose-pine base
    property color fg:    "#e0def4"  // text
    property color muted: "#6e6a86"  // muted
    property color iris:  "#c4a7e7"  // iris (accent)
    property color surf:  "#1f1d2e"  // surface

    ColumnLayout {
        anchors.centerIn: parent
        width: 320
        spacing: 14

        Text {
            text: "Rosé Pine"
            color: root.iris
            font.pixelSize: 30
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
        }
        ComboBox {
            id: user
            Layout.fillWidth: true
            model: userModel
            textRole: "name"
            currentIndex: userModel.lastIndex
        }
        TextField {
            id: password
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: "Password"
            focus: true
            color: root.fg
            palette.base: root.surf
            palette.text: root.fg
            onAccepted: sddm.login(user.currentText, password.text, sessionModel.lastIndex)
        }
        Button {
            text: "Log In"
            Layout.fillWidth: true
            onClicked: sddm.login(user.currentText, password.text, sessionModel.lastIndex)
        }
        Text {
            id: msg
            color: root.muted
            Layout.alignment: Qt.AlignHCenter
            text: ""
        }
    }
    Connections {
        target: sddm
        function onLoginFailed() { msg.text = "Login failed"; password.selectAll(); password.forceActiveFocus() }
    }
}
QML

mkdir -p /usr/local/etc/sddm.conf.d
cat >/usr/local/etc/sddm.conf.d/10-rose-pine.conf <<'SDDMCONF'
[Theme]
Current=rose-pine
CursorTheme=BreezeX-RosePine-Linux
[General]
Numlock=on
SDDMCONF

### 10. Default applications ─────────────────────────────────────────────────────
# xdg-utils works on FreeBSD; the Linux `alternatives` system does not exist, so
# the kitty x-terminal-emulator block is dropped. VSCodium has no FreeBSD port
# yet, so no editor default is registered.
as_user "XDG_CONFIG_HOME='$TARGET_HOME/.config' xdg-settings set default-web-browser librewolf.desktop" || true
for scheme in http https; do
  as_user "XDG_CONFIG_HOME='$TARGET_HOME/.config' xdg-mime default librewolf.desktop x-scheme-handler/$scheme" || true
done
for mt in video/mp4 video/x-matroska audio/mpeg audio/x-wav; do
  as_user "XDG_CONFIG_HOME='$TARGET_HOME/.config' xdg-mime default vlc.desktop $mt" || true
done

echo
echo "============================================================"
echo " Bootstrap complete."
echo "   * Switch the VM's display device to virtio-gpu, then REBOOT"
echo "     (loads virtio_gpu -> /dev/dri -> accelerated, tear-free X,"
echo "      and starts the SDDM login greeter)."
echo "   * At the SDDM greeter, pick the 'Qtile' session and log in."
echo "     (No DM? 'startx' also works via ~/.xinitrc.)"
echo "   * Editor: VSCodium/code-oss has no FreeBSD port yet - install"
echo "     your choice separately (mod+e is wired to it)."
echo "============================================================"
