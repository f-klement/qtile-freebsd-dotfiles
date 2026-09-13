# qtile-freebsd-dotfiles

A minimal **FreeBSD 14+** qtile dotfiles setup (X11).

Ported from a Rocky/RHEL 8 workstation config. Everything the WM needs is
installed from the native `pkg` repository — no third-party repos, no
from-source builds, and none of the Linux-only kernel/session tuning the EL8
version carried. The window-manager config, the volume readout (base-system
`mixer(8)`), the network widget (default-route NIC), and the update widget
(`pkg`) are all FreeBSD-native.

The bootstrap script (`x11_bootstrap.sh`) provisions: Xorg + qtile, the WM
utilities (picom, dunst, rofi, feh, xss-lock, i3lock, copyq), LibreWolf,
nautilus, flameshot, the Rosé Pine GTK theme + BreezeX cursor, fonts, and the
common dev tooling (node, uv, rust, ripgrep, fzf, direnv, podman).

Deploy the configs with GNU stow. The setup script needs root (for `pkg`).

```sh
pkg install -y bash stow git          # if not already present
chmod +x x11_bootstrap.sh
sudo ./x11_bootstrap.sh
stow .
echo 'exec qtile start' > ~/.xinitrc   # then `startx`, or pick Qtile in your DM
```

## Notes

- **Editor:** VSCodium / code-oss has no FreeBSD port yet — install your choice
  separately and it will be picked up by `mod+e`.
- **Audio:** volume is driven through the base-system `mixer(8)`; PulseAudio is
  installed for `pavucontrol` and app routing.
- **Containers:** `podman` is installed, but FreeBSD podman uses ZFS + jails and
  needs host-specific setup — configure it per the FreeBSD handbook when needed.
- **Guest tools:** this image targets KVM/virtio (`qemu-guest-agent`); swap in
  the appropriate guest package for other hypervisors.
