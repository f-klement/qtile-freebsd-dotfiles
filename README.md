# qtile-dotfiles

A minimal RHEL/EL qtile dotfiles setup (X11).

The bootstrap detects the platform rather than assuming EL8: it maps
powertools/crb, probes the kernel for the best zswap zpool + compressor,
tests for native (non-fuse) rootless overlay, and prefers distro packages
over from-source builds where they exist. That makes it far less work to
lift onto EL9/10.

Containers are rootless podman driven by the docker CLI via DOCKER_HOST;
there is no docker daemon. See `archive/docs/` for the reasoning behind the
session and memory hardening in section 9.5.

deploy configs with gnu stow
the setup file will ask for the root password

```bash
chmod +x el_x11_bootstrap.sh
sudo ./el_x11_bootstrap.sh
stow .
```
