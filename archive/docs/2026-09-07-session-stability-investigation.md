# Session stability investigation — BEUCLX-22

**Date:** 2026-09-07  **Host:** BEUCLX-22 (Rocky Linux 8.10, VMware guest, 4 vCPU, 7.6 GB RAM, rotational disk)
**Session:** xrdp → Xvnc `:10` @ 5040x1920x32 → `gnome-session-binary` → qtile 0.31.0

## Problem

The qtile session froze under load and tolerated fewer open applications than a
colleague's stock GNOME session on the same hardware allowance — the opposite of
what a "lightweight WM" should do.

## Root causes (in order of impact)

### 1. The session was never lightweight — it is GNOME *plus* qtile

`gnome-session-binary` was launching the stock `gnome.session`, whose
`RequiredComponents` pulled in **19 `gsd-*` daemons** plus tracker miners, and
then qtile on top. A stock GNOME session runs the same `gsd-*` stack with
`gnome-shell` where this one has qtile — so this session was strictly *heavier*,
never lighter.

`gnome-shell` was also being started as a required component and then killed 5
seconds later by `bin/starting-qtile.sh`, so it was paid for and discarded.

### 2. qtile's glibc heap ratcheted to 364 MB (the actual freeze)

| | before | after restart |
|---|---|---|
| qtile total | **375 MB** (168 resident + 207 swapped) | **62 MB** (0 swapped) |
| `[heap]` | 346 MB (335 MB of brk address space) | 10 MB |

Mechanism: glibc's main arena grows via `brk()` and only trims when the *top*
free chunk exceeds `M_TRIM_THRESHOLD` — a threshold glibc raises dynamically
every time it sees a large free. The polling widgets fragment the arena so the
top chunk stays small and the threshold drifts upward until it effectively never
trims. The heap only grows.

Why that freezes the desktop: qtile is a **single-threaded Python asyncio loop
that is the window manager**. Every map/unmap/focus/keypress goes through it.
CPython's gen-2 GC walks the whole object graph, so it touches all 335 MB — 202 MB
of which was on a rotational disk. For the duration of that walk the WM dispatches
no X events.

Aggravating factor found during validation: **three bars, one per screen**, so
every polling widget existed ×3 (~345,600 widget updates/day), and `CheckUpdates`
was spawning **three concurrent `dnf` processes** every 30 min — the likely source
of 44 `Failed to start dnf makecache` errors (rpmdb lock contention).

System-wide reclaim pressure at time of investigation:

```
pgmajfault        8,088,001
pgscan_direct   344,637,951
pgsteal_direct  180,404,536
allocstall_movable 3,431,663
pswpout  3,589,014 pages (~14.3 GB)   pswpin 1,070,496 pages (~4.3 GB)
```

### 3. zswap silently degraded to a mode that hurts under load

```
kernel: zswap: zpool z3fold not available, using default zbud
```

`CONFIG_Z3FOLD is not set` on this kernel — the requested zpool never existed, so
zswap fell back to **zbud** (2 compressed pages per physical page, ~1.7:1 ceiling)
instead of the intended z3fold (~3:1). With `max_pool_percent=20` that reserved
**~1.53 GB of RAM** to store only ~2.6 GB of compressed pages.

Worse, `accept_threshold_percent=90`: once the pool fills, zswap **rejects** new
pages and they go straight to the disk partition — while the 1.53 GB pool stays
resident. Under sustained pressure you got full disk swapping *plus* 1.53 GB less
RAM than with no zswap at all.

`CONFIG_CRYPTO_LZ4` and `CONFIG_CRYPTO_ZSTD` are also unset — **lzo is the only
compressor this kernel has.** `CONFIG_ZSMALLOC=y` is present and is the fix.

### 4. VSCodium's Java language servers could reach ~4 GB of heap

Two OOM kills of `snap.codium.codium-*.scope` (1.4 GB and 3.0 GB anon RSS).
Cause found in the extension defaults:

| | default max heap |
|---|---|
| `redhat.java` (Eclipse JDT LS, 117 jars) | **`-Xmx2G`** |
| `sonarsource.sonarlint` (no vmargs set) | JVM default = **1918 MB** on this box |
| `redhat.vscode-xml` (lemminx) | `-Xmx64M` (small, but a third JVM) |

On a 7.6 GB box alongside Brave, docker and two tomcat containers, that is the
whole budget. `redhat.java`, `vscode-maven` and `vscode-java-debug` are already
correctly scoped to Java projects by their `activationEvents`
(`workspaceContains:pom.xml`, `build.gradle`, `.classpath`, `onLanguage:java`) —
so the problem was never scope, it was the heap ceiling.

### 5. tuned `virtual-guest` is tuned for throughput, not latency

`vm.dirty_ratio = 30` allowed **2.3 GB** of dirty pages to queue before throttling
writers, then flushed to a rotational disk — a system-wide stall on every
`docker build` / `npm install`.

### Not a cause (investigated and dismissed)

**Xvnc / three-monitor layout.** The 5040x1920 framebuffer is the correct bounding
box of `1920x1080 +0+840`, `1920x1200 +3120+382`, `1200x1920 +1920+0`. ~31% of it
is dead space between differently-sized screens, but that is **irreducible** — the
portrait screen forces height 1920 and horizontal tiling forces width 5040.
Xvnc used only **1528 s of CPU over 6d22h (0.26% average)**, which does not
support it being a primary cause. It is a 320 MB fixed memory cost, nothing more.

---

## Changes applied

### A. qtile — `~/.dotfiles` (git-tracked)

`.config/qtile/config.py`
- `widget.Net(interface="eth0")` — stops enumerating `docker0`/`virbr0`/`br-*`/`veth*` every poll
- `Net` 3s→5s, `Memory` 2s→5s, `CPU` 2s→5s (~345,600 → ~155,520 updates/day)
- `CheckUpdates` scoped to screen 0 via the existing `init_widgets` flag (144 → 48 dnf spawns/day)
- `malloc_trim(0)` on a 900 s timer via `@hook.subscribe.startup_complete`

`bin/starting-qtile.sh`
- `MALLOC_TRIM_THRESHOLD_=131072` — pins the threshold, disabling glibc's dynamic drift
- `MALLOC_ARENA_MAX=2` — caps per-thread arenas (qtile runs ~9 threads)

`.config/qtile/autostart_x11.sh`
- Wallpaper list enumerated once at startup instead of a recursive `find` every 300 s
- `xss-lock` moved off `dbus-run-session` onto the session bus (it had a private bus,
  so idle/inhibit signalling between apps and the locker could not work)

**Verify:** `grep -E 'VmRSS|VmSwap' /proc/$(pgrep -f 'qtile start')/status` — expect ~60–80 MB, 0 swap
**Revert:** `git -C ~/.dotfiles checkout .config/qtile bin/starting-qtile.sh`

### B. Session trim

Tier A — user-level, `~/.config/autostart/*.desktop` with `Hidden=true` (11 entries):
tracker ×4, `SettingsDaemon.Account`, `DiskUtilityNotify`, `gnome-software-service`,
`gsettings-data-convert`, `gnome-shell-overrides-migration`, `user-dirs-update-gtk`,
`orca-autostart`.

Tracker was *also* a systemd user unit *and* D-Bus activated, so additionally:
```
systemctl --user mask tracker-{store,miner-fs,miner-apps,extract,writeback}.service
gsettings set org.freedesktop.Tracker.Miner.Files index-recursive-directories "[]"
gsettings set org.freedesktop.Tracker.Miner.Files index-single-directories "[]"
gsettings set org.freedesktop.Tracker.Miner.Files enable-monitors false
gsettings set org.freedesktop.Tracker.Miner.Files crawling-interval -2
```
(`tracker-extract` had 25+ coredumps in one afternoon on 2026-08-05.)

Tier B — `/usr/local/share/gnome-session/sessions/gnome.session`, which shadows the
RPM-owned file because `/usr/local/share` precedes `/usr/share` in this session's
`XDG_DATA_DIRS`. Exactly one line differs from stock; all 89 `Name[...]` lines preserved.

```
RequiredComponents=org.gnome.SettingsDaemon.XSettings;org.gnome.SettingsDaemon.Keyboard;org.gnome.SettingsDaemon.MediaKeys;
```

Kept: **XSettings** (GTK theme/font/DPI for every GTK app), **Keyboard** (XKB layout —
this is a German-layout box), **MediaKeys**.
Dropped: `org.gnome.Shell` (was started then killed), A11ySettings, Clipboard (copyq
already does this), Color, Datetime, Housekeeping (**loses the low-disk-space warning**),
Mouse, Power (source of the recurring `Unable to inhibit system: AccessDenied` spam),
PrintNotifications, Rfkill, ScreensaverProxy, Sharing, Smartcard, Sound, Wacom.

`gnome-session-binary` still starts and holds its place in the process tree, so
**whatever monitors it for reboot is unaffected** — only its child list shrinks.

**Verify:** after next login, `pgrep -c '^gsd-'` should be ~3, not 20
**Revert:** `rm /usr/local/share/gnome-session/sessions/gnome.session`; delete the
`Hidden=true` files; `systemctl --user unmask tracker-*`

> Do **not** set `XDG_CURRENT_DESKTOP=Qtile` at session level to achieve this — it
> would skip every `OnlyShowIn=GNOME` autostart including **gnome-keyring**
> (pkcs11/secrets/ssh), which this session depends on.

### C. Kernel / sysctl

`/etc/sysctl.d/99-desktop-latency.conf`
```
vm.dirty_bytes = 268435456          # 256 MB, was effectively 2.3 GB
vm.dirty_background_bytes = 67108864 # 64 MB
# vm.swappiness = 100   <- ONLY after zswap zpool is confirmed zsmalloc
```
Setting `*_bytes` zeroes the corresponding `*_ratio`, which is intended.

Kernel cmdline via `grubby` (**pending reboot**):
```
zswap.enabled=1 zswap.zpool=zsmalloc zswap.compressor=lzo zswap.max_pool_percent=20
```
Confirmed staged: `sudo grubby --info=DEFAULT | tr ' ' '\n' | grep zswap`

### D. VSCodium: snap → RPM, plus extension audit

The snap was **classic** confinement, so it already wrote to `~/.config/VSCodium`
and `~/.vscode-oss` — **config migration was a no-op**. The snap was also the stale
side: 1.105.17075, last refreshed 2026-02-12, versus 1.126.04524 upstream. VSCodium
is not in Rocky or EPEL; the maintained path is the project's own RPM repo.

Engine audit: highest requirement across all 75 extensions was `^1.105.1`
(`supabase.postgrestools`) — i.e. the snap was *at the edge* of what two extensions
needed. 1.126 satisfies everything.

**Extensions: 76 → 28** (see the Confirmed Outcomes addendum; 783 MB quarantined to
`~/.vscode-oss/extensions-quarantine-20260907/`, restore by moving back).

Removed as redundant/unused — each on evidence:
- `dbcode.dbcode-1.38.0` (168 MB) — duplicate of 1.38.1, **both activating eagerly**
- `vscode-data-preview` (137 MB), `docthis` (37 MB) — unmaintained, no settings reference
- 8 unused themes (active theme is `Catppuccin Latte`)
- legacy Test Explorer trio — superseded by native testing API in VS Code 1.59
- `ms-azuretools.vscode-docker` 2.0.0 — deprecated shim; `vscode-containers` is configured
- `dotjoshjohnson.xml` — redundant with `redhat.vscode-xml`
- 3 snippet packs declaring `engine: ^0.10.x` (VS Code 2016)
- both Gemini extensions (240 MB + 2 MB)
- `rvest.vs-code-prettier-eslint` — prettier consolidated onto `esbenp.prettier-vscode`
- `react-native-directory` (no RN in 29 workspaces), `rail5.bashpp` (0 `.bpp`),
  `jetmartin.bats` (0 `.bats`), `unifiedjs.vscode-mdx` (0 `.mdx`),
  `firefox-devtools.vscode-firefox-debug` (Brave/Chromium user)
- both manifest-only extension packs (members stay installed; the markdown pack
  referenced 4 uninstalled members it would keep trying to re-add)

Kept on evidence: `gitlab-workflow` (16 repos across `gitlab.bev.gv.at` + `gitlab.com`),
`rainbow-csv` (52 `.csv`), `helm-intellisense` (`egisy-helm`), `open-remote-ssh`
(3 remote workspaces), `even-better-toml` (7 `.toml`), SonarLint (connected mode
against SonarQube at `10.70.5.80:9001` with 6 rule overrides).

Settings changes — `~/.config/VSCodium/User/settings.json` (backup: `settings.json.pre-tuning`):
```jsonc
"xml.server.preferBinary": true,     // ships lemminx-linux-x86_64 -> no third JVM
"java.jdt.ls.vmargs": "... -Xmx1G -Xms64m ...",   // was -Xmx2G
"java.import.gradle.enabled": false, // 4 pom.xml, 0 build.gradle in ~/projects
"sonarlint.ls.vmargs": "-Xmx1024m",  // was uncapped -> JVM default 1918 MB
"bashIde.shellcheckPath": "",        // shellcheck not installed; stop failed spawns
"[typescript]": { "editor.defaultFormatter": "esbenp.prettier-vscode" }
```
Net effect: roughly **2 GB of worst-case JVM heap removed** from the IDE.

---

## Pending

- [ ] `sudo bash ~/codium-migrate-root.sh`, then verify and `sudo snap remove --purge codium` (frees ~1.1 GB + 2 loop mounts)
- [ ] Log out / back in — picks up MALLOC env vars and the trimmed session
- [ ] **Reboot** — activates zswap `zsmalloc`
- [ ] After reboot: `cat /sys/module/zswap/parameters/zpool` must print `zsmalloc`, and `dmesg | grep zswap` must NOT say "not available"
- [ ] Only then: uncomment `vm.swappiness = 100` and `sudo sysctl --system`
- [ ] Watch qtile `VmRSS`+`VmSwap` over 48 h to confirm the heap stays flat

## Deliberately not done

- **earlyoom** — installed (`earlyoom-1.6.2`) but masked since 2026-07-20. Left masked
  at the user's request: with the stock `/etc/default/earlyoom` (no `--avoid`/`--prefer`)
  it kills the largest-RSS process, which is a cold-starting Electron IDE. It would
  need `--avoid '^(qtile|Xvnc|xrdp.*)$' --prefer '^(codium|brave|java)$'` to be safe.
  Consequence: the kernel OOM killer remains the only backstop.
- **`java.autobuild.enabled: false`** — would save more but degrades Java DX (errors
  stop updating until an explicit build).
- Orphaned settings left in place: `postgresExplorer.connections` and `vs-kubernetes`
  both reference extensions that are no longer installed. The postgres block carries a
  host and username in plaintext.

## Unrelated finding

`dockerd` runs with `-H tcp://0.0.0.0:2375` — an unauthenticated, unencrypted,
root-equivalent API on every interface. Anyone who can reach that port can start a
privileged container and own the host.

## Backups

| what | where |
|---|---|
| qtile configs (pre-change) | `~/.config/qtile-stability-backup-20260907-095417/` |
| VSCodium settings/keybindings/snippets + extension list | `~/codium-migration-backup-20260907-100852/` |
| VSCodium settings (pre-tuning) | `~/.config/VSCodium/User/settings.json.pre-tuning` |
| quarantined extensions (29) | `~/.vscode-oss/extensions-quarantine-20260907/` |
| root change scripts | `~/stability-fixes-root.sh`, `~/codium-migrate-root.sh` |

---

## Addendum — same day, later passes

### dnf: the metadata lock was blocking installs

The VSCodium install stalled 11 minutes. Cause: `dnf-makecache.timer` fired,
took `/var/cache/dnf/metadata_lock.pid`, and refreshed every remote repo through
the proxy while the install queued behind it. `dnf -q` suppressed the "waiting
for process to finish" message, so it looked hung. Same timer is behind the 44
`Failed to start dnf makecache` journal errors, and it was racing the three
qtile `CheckUpdates` widgets.

Second stall, after the lock cleared: `repo_gpgcheck=1` on the new vscodium repo
made dnf build a throwaway gpgme keyring under `/var/tmp` and respawn `gpg-agent`
in a retry loop with no network activity. Entropy was fine (3758/4096) — it is the
gpgme path itself. Fixed by `repo_gpgcheck=0`; `gpgcheck=1` stays, which is the
one that matters (it verifies each RPM against the key imported by `rpmkeys`).

Applied via `~/repo-prune-root.sh`:
- Removed `google-chrome-stable`, `google-cloud-cli`, `code` (Microsoft VS Code
  1.134.0). Configs left in place at `~/.config/google-chrome`, `~/.config/Code`.
- Installed system `ShellCheck`, replacing the 16 MB bundled copy in
  `timonwong.shellcheck`; `bashIde.shellcheckPath` now points at it.
- Disabled repos: `google-chrome`, `google-cloud-cli`, `code`,
  `rpmfusion-free-updates` (**0 installed packages originate from RPM Fusion**),
  `epel-testing` (**a testing repo, enabled by accident**).
- **`brave-browser` deliberately kept enabled** — it provides the native Brave.
- `dnf-makecache.timer` disabled, `dnf-makecache.service` masked.
- `/etc/dnf/dnf.conf`: `fastestmirror`, `max_parallel_downloads=10`,
  `skip_if_unavailable=True`, `timeout=30`, `retries=3`.

Note: `nodejs-22.22.3-1nodesource` is installed but both nodesource repos are
`enabled=0`, so node receives no updates. Left as-is.

### Brave: flatpak → native RPM (`~/brave-migrate.sh`)

The flatpak was carrying two versions (1.93.136 and 1.88.138) — the same
stale-runtime pattern as the codium snap.

Migration is far less painful than it looks, because the hard part is already
shared. Brave on Linux does **not** keep `os_crypt.encrypted_key` in `Local State`
(that field is Windows/DPAPI); it reads the key from gnome-keyring. That entry —
`Brave Safe Storage`, schema `chrome_libsecret_os_crypt_password_v2`,
`application=brave` — is used identically by the native build, so cookies and
saved passwords decrypt after the move.

So the migration is one profile copy:
`~/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser` →
`~/.config/BraveSoftware/Brave-Browser` (427 MB of config; the 1.8 GB `cache/`
is discarded). Carries bookmarks, history, cookies, Login Data, Preferences and
all 7 extensions (Dark Reader, React Developer Tools, **Proton Pass**, Toby,
Medium Parser, Modify Header Value, +1).

The script gates on version: Chromium refuses a profile written by a newer build,
so it aborts if the RPM is older than the flatpak.

Both launchers now autodetect, so nothing breaks before or after:
- `config.py`: `browser = "brave-browser" if shutil.which("brave-browser") else "flatpak run com.brave.Browser"`
- `autostart_x11.sh`: `command -v brave-browser` with a flatpak fallback

### Extensions — passes 3 and 4

**76 → 32, 2.3 GB → 1.6 GB, eager activations 25 → 13.**

Dropped as redundant: `docker.docker` (41 MB — 8× heavier than
`ms-azuretools.vscode-containers`, which the settings already reference),
`jeff-hykin.better-dockerfile-syntax`, `bierner.docs-view` (45 MB),
`ritwickdey.liveserver` (34 MB, eager — **both TS projects have `vite.config.ts`**),
`3timeslazy.vscodium-devpodcontainers` (eager — **no `devcontainer.json`, no devpod
binary**), `formulahendry.code-runner`, `bierner.color-info`, `bierner.emojisense`,
`rpinski.shebang-snippets`, `foxundermoon.shell-format`,
`garlicbreadcleric.pandoc-markdown-syntax`, `edwinkofler.vscode-assorted-languages`,
`mgesbert.python-path`, `rogalmic.bash-debug`, `timonwong.shellcheck`.

**Kept on evidence, against the initial recommendation:**
`bierner.markdown-mermaid` — 2 files actually use ```` ```mermaid ````
(`egisy-helm/docs/architecture.md`, `egisy-ts/docs/architektur-egisy-verbund.md`).

**Still held — genuine tradeoffs, not waste:**
- `tamasfe.even-better-toml` (69 MB) for 7 `.toml` files; no lighter TOML LSP exists
- `dbcode.dbcode` (168 MB, eager) — `mtxr.sqltools` + pg driver is ~25× lighter but
  means re-entering the connection and losing the UI

### Scripts

| script | needs root | purpose |
|---|---|---|
| `~/stability-fixes-root.sh` | yes | sysctl, zswap, session trim (**run**) |
| `~/codium-migrate-root.sh` | yes | added repo + key (**stalled on repo_gpgcheck**) |
| `~/codium-migrate-root2.sh` | yes | retry with `repo_gpgcheck=0` |
| `~/repo-prune-root.sh` | yes | package/repo pruning, makecache off, ShellCheck |
| `~/brave-migrate.sh` | no (sudo's internally) | Brave flatpak → RPM |

---

## Confirmed outcomes (end of session)

Scope note: **no infrastructure changes.** Everything here is guest-side and
reversible on this VM as it stands.

### Ran and verified

| script | result |
|---|---|
| `stability-fixes-root.sh` | `dirty_bytes`=256 MB live; zswap `zsmalloc` staged (confirmed via `grubby`); session override present |
| `codium-migrate-root2.sh` | `codium-1.126.04524-el8` installed, snap removed (was 1.105.17075, stale since Feb) |
| `repo-prune-root.sh` | removed `google-chrome-stable`, `google-cloud-cli`, `code`, `nodejs`; installed `ShellCheck`; **enabled repos 10 → 6**; `dnf-makecache.timer` disabled; dnf.conf tuned |
| `brave-migrate.sh` + `brave-fix.sh` | `brave-browser-1.94.121` (> flatpak 1.93.136, version gate passed); flatpak + 2.2 GB removed |

`docker builder prune -a` reclaimed **12.96 GB** of build cache.

### qtile — the headline fix

375 MB (168 resident + 207 swapped) → **66 MB, 0 swapped**. Caveat: `exec`
preserves process start time, so the uptime reading is misleading — confirm the
heap stays flat over 48 h before calling the ratchet solved.

### Two mistakes I made, and what they cost

**1. Brave `ScriptCache`.** My `rsync --exclude='*Cache/'` also matched
`Default/Service Worker/ScriptCache` — not a disposable cache, but where
Chromium stores service worker scripts, indexed by `Service Worker/Database`.
Result: 132 files → 2, and every extension logged `DidStartWorkerFail: 5` in a
loop. The repair script then failed because the flatpak profile had already been
deleted, leaving an *empty* Service Worker dir — which turned out to be the
correct end state: Chromium rebuilt it cleanly on launch (130 files, ScriptCache
back to 122) and extensions re-registered from their own bundled scripts.
Everything else survived intact: `Local Extension Settings` 22 MB (Proton Pass
vault), `IndexedDB` 51 MB, `Local Storage`, `CacheStorage`.

**2. Extension quarantine via directory moves.** I moved 44 extension directories
without updating `extensions.json`, so VSCodium found 44 dangling manifest
entries and alerted on all of them; six were then **re-downloaded** from Open VSX
because the manifest still claimed them. Compounding it, uninstalling
`pinage404.bash-extension-pack` cascaded and removed three members I wanted kept,
including `mads-hartmann.bash-ide-vscode`. Correct method is
`codium --uninstall-extension <id>`, which updates the manifest atomically.
Final state: **28 extensions**, CLI-managed and consistent.

Not restored (removed during the bulk UI cleanup, left out by choice):
`davidanson.vscode-markdownlint`, `yzhang.markdown-all-in-one`,
`bierner.markdown-preview-github-styles`.

### Brave: flatpak → native RPM

Config migration was a non-issue because the encryption key is shared: Brave on
Linux does **not** store `os_crypt.encrypted_key` in `Local State` (Windows/DPAPI
only) — it reads gnome-keyring entry `Brave Safe Storage`
(schema `chrome_libsecret_os_crypt_password_v2`), which the native build uses
identically. All 7 extensions carried over, including Proton Pass.

GPU noise: this VMware guest has no 3D, so Brave probed vaapi → zink → DRM/KMS
and failed at each (~40 `DRM_IOCTL_MODE_CREATE_DUMB` lines per launch). The
flatpak hid this because Brave auto-selected `--disable-gpu-compositing` inside
the sandbox. Fixed with `~/.local/bin/brave-browser`, a PATH wrapper
(`~/.local/bin` precedes `/usr/bin`) adding `--disable-gpu
--disable-software-rasterizer --disable-gpu-compositing`. It covers shell and
PATH launches; `~/.local/share/applications/brave-browser.desktop` covers menu
launches. qtile config and `autostart_x11.sh` call plain `brave-browser` so the
wrapper stays the single source.

Residual `Failed to create API on Chrome object` (4 lines) traces to **The
Marvellous Suspender** requesting `chrome.identity`, which Brave does not
implement. Cosmetic; tab suspension is unaffected. Only visible when launching
from a terminal.

### node

Comes exclusively from nvm (`~/.nvm`, v24.9.0, wins on PATH). The nodesource RPM
(22.22.3) was removed — `rpm -e --test` confirmed nothing depended on it — and
both nodesource repos disabled.

## Docker → Podman migration (prepared, NOT yet run)

Decisions taken: **keep docker solely as minikube's driver** (minikube is pinned
to `driver=docker`; its podman driver is experimental), and run **rootless
podman** for everything else.

Why it is viable here: no privileged ports (lowest bound is 3000), nothing mounts
`docker.sock`, and no `network_mode: host` / `privileged` / `deploy` / `extends`
across the 19 compose files.

To preserve: two authenticated Nexus registries (`docker.bev.gv.at` —
**currently returning 503, likely decommissioned** — and `docker2.bev.gv.at`,
which is a pull-through proxy for Docker Hub), the corporate proxy, 23 named
volumes (~1 GB excluding minikube's 2.4 GB and the regenerable `*_temp`), 17
images, 19 Dockerfiles and 10+ shell scripts.

Key design points:
- **Compose v2 over podman's Docker-compatible socket**, not `podman-compose`
  (EPEL ships 1.0.6, weakest exactly at `condition: service_healthy`, which is used).
- `DOCKER_HOST` redirects all scripts and compose transparently; a
  `~/.local/bin/minikube` wrapper forces `unix:///var/run/docker.sock` so
  minikube is unaffected.
- Volumes migrate by tar **out of a docker container and into a podman one** —
  extracting inside the podman container keeps in-container UIDs correct under
  the user namespace instead of flattening them to the host UID.
- `NO_PROXY` gains `.bev.gv.at` (the docker daemon omits it, so Nexus pulls
  needlessly traverse the proxy; both registries verified reachable directly).

**Storage driver.** Rootless podman on EL8 defaults to `fuse-overlayfs`
(userspace FUSE, ~2–5× slower on metadata). This kernel supports unprivileged
overlay mounts — verified working in a user namespace — so
`~/.config/containers/storage.conf` deliberately omits `mount_program` to take
the kernel path. Stage 2 warns if fuse appears anyway. `metacopy`/`redirect_dir`
left off (default `N` here; Red Hat disables them for correctness/CVE reasons).

**Podman version.** Rocky 8 ships 4.9.4 and that is terminal — `container-tools:rhel8`
is the rolling stream and 8.10 is the final minor release. Upstream is 6.1.1.
Homebrew has a 6.1.1 Linux bottle but pulls ~180 formulae including its own
glibc, gcc and systemd, which is the wrong trade for a container runtime that
must integrate with host systemd and cgroups. The binding constraint is the
**4.18 kernel** anyway: idmapped mounts need 5.12+, and `passt` (pasta
networking) is not packaged for EL8, so podman 6 here would run with most of its
post-4.9 advantages disabled. 4.9.4 covers everything required.

| script | run as | purpose |
|---|---|---|
| `~/podman-install-root.sh` | root | install podman/skopeo/buildah, linger, close docker's TCP 2375 |
| `~/podman-stage2.sh` | admin | socket, auth check, volume migration, DOCKER_HOST + minikube wrapper |
| `~/iosched-test.sh` | root | optional, self-reverting A/B of mq-deadline vs none |

## Still pending

- [ ] Log out / back in — MALLOC env + trimmed session (`gsd` 20 → ~3)
- [ ] **Reboot** — activates zswap `zsmalloc`; then `cat /sys/module/zswap/parameters/zpool` must read `zsmalloc` before uncommenting `vm.swappiness=100`
- [ ] Restart codium — purges 19 stale extension dirs
- [ ] Watch qtile `VmRSS`+`VmSwap` over 48 h
- [ ] Podman migration (stage 1, then stage 2)

---

## Docker → Podman: as actually executed (completed, verified)

Final state: **podman 4.9.4 rootless, native kernel overlay, 20/20 volumes
migrated, all stacks building and running.** The docker daemon is gone; the
docker *client* remains and drives podman.

### The blocker that reshaped the plan

`containerd.io` declares `Obsoletes: runc` **and** `Conflicts: runc`; podman's
`containers-common` has a hard `Requires: runc`. Docker-CE and podman cannot
coexist on EL8 — no dnf flag works around it.

Resolution: remove the **daemon** (`docker-ce`, `containerd.io`,
`docker-ce-rootless-extras`), keep the **client** (`docker-ce-cli`,
`docker-compose-plugin`). Those are standalone Go binaries requiring nothing
from the daemon, and `docker-ce-cli` conflicts only with `docker`/`docker-ee*`,
not with podman or runc. `DOCKER_HOST` then points the client at podman's
Docker-compatible socket, so all 19 compose files and 10+ project scripts work
unmodified. `docker info` reports `ServerVersion 4.9.4-rhel`.

### Execution order (matters)

Podman cannot install until docker is removed, but volumes must be exported
while docker still runs. Hence three stages:
`podman-stage0-export.sh` (export + manifest) → `podman-swap-root.sh`
(daemon out, podman in) → `podman-stage2.sh` (overlay gate, socket, import).
Stages 1 and 2 refuse to run without stage 0's manifest.

### Storage: native kernel overlay, not fuse

Rootless podman on EL8 defaults to `fuse-overlayfs` (userspace FUSE, ~2-5x
slower on metadata). RHEL 8 backports unprivileged overlay mounts — verified
working in a user namespace — so `mount_program` is deliberately omitted at both
system and user level. Stage 2 gates on this **before** importing any data, and
resets an empty store if fuse was picked. Confirmed:
`driver=overlay, options=map[overlay.ignore_chown_errors:true]`.

### My script bugs, and what they cost

1. **`clean_requirements_on_remove`.** I verified `docker-ce-cli` and
   `docker-compose-plugin` don't *Require* docker-ce and concluded they would
   survive. dnf's default autoremove takes packages originally installed **as
   dependencies** once orphaned, so both were swept up. Recovered by reinstalling
   from `docker-ce-stable` (enabled for one transaction). Should have used
   `--noautoremove`.
2. **minikube premise.** I recommended keeping docker for minikube based on
   `minikube profile list` showing a profile. The container had been deleted in
   March; `minikube status` errored with "No such container". The decision was
   posed on a false premise.
3. **rsync `--exclude='*Cache/'`** also matched `Service Worker/ScriptCache`
   (Brave) — recorded in the earlier addendum.

### Three latent environment bugs the migration exposed

All three predate podman; Docker's layer cache had hidden them for months.

1. **apt reads only lowercase `http_proxy`.** The Dockerfiles set `ENV
   HTTP_PROXY` uppercase only. The podman **CLI** injects the lowercase pair,
   but builds driven through the **API socket** (how compose builds) get no
   injection — so apt saw no proxy and fell back to DNS. **This network has no
   DNS at all**: `dig` to 1.1.1.1 and 8.8.8.8 times out from host and container
   alike; everything external goes through the proxy, and internal names resolve
   only from `/etc/hosts` (`nsswitch: files ...`).
   Fixed with **predefined proxy build args** (`http_proxy` etc. need no `ARG`
   line), set in local overrides — no shared file touched.
2. **`.zshrc` leading comma:** `export NO_PROXY=$NO_PROXY,...` with `$NO_PROXY`
   empty produced `,192.168...`. An empty entry matches *every* host in many
   proxy implementations, disabling the proxy wholesale. Changed to
   `${NO_PROXY:+$NO_PROXY,}`.
3. **`.dockerignore` does not recurse.** `node_modules` matched only the top
   level, so nested copies shipped in every build context: egisy-ts 468 MB,
   template-js 440 MB, egisy-ts-demo 226 MB. Added `**/node_modules`.
   egisy-ts build context: **108.7 MB -> 2.233 MB**.

### Shared-repo constraint (why compose files were NOT edited)

podman 4.9's compat build endpoint cannot parse the `extrahosts` query parameter
(`invalid character 'e' in literal null`). Nine compose files set
`build: extra_hosts`. Deleting it would work here — podman seeds container
`/etc/hosts` from the host's — but **Docker does not**, and with no DNS those
entries are load-bearing for the 2-3 colleagues on `puko`, `default_backend` and
`egisy-java`.

Instead: a local `docker-compose.override.yml` per project using compose 2.24+
`!reset`, registered in `.git/info/exclude` (untracked, so the shared
`.gitignore` is untouched). `git status` shows zero changes from it.
The same overrides carry the lowercase proxy args.

### Kept: minikube

Reversed from the migration plan. The cluster must be recreated on the podman
driver; `driver=docker` is impossible now. Two prerequisites were missing:
- **cgroup v2 delegation** was only `memory pids`; rootless Kubernetes needs
  `cpu cpuset io memory pids`. Needs `/etc/systemd/system/user@.service.d/delegate.conf`
  and a session restart.
- **crun** absent (podman pulled runc, since containers-common requires it).
Scripts: `~/minikube-podman-setup.sh` (root), `~/minikube-podman-start.sh` (user).
Start uses `--container-runtime=containerd` (rootless cannot use the docker
runtime) and modest `--cpus=2 --memory=2200mb` given 4 vCPU / 7.6 GB.

### Scripts

| script | as | purpose |
|---|---|---|
| `~/podman-stage0-export.sh` | admin | export volumes + manifest (docker still up) |
| `~/podman-swap-root.sh` | root | daemon out, client kept, podman in |
| `~/podman-fix-cli.sh` | root | recover the autoremoved docker client |
| `~/podman-stage2.sh` | admin | overlay gate, socket, auth, import, DOCKER_HOST |
| `~/docker-cleanup.sh` | root | remove /var/lib/docker, configs, repos |
| `~/minikube-podman-setup.sh` | root | cgroup delegation + crun |
| `~/minikube-podman-start.sh` | admin | recreate cluster on podman |

### Shell environment added

```
DOCKER_HOST=unix:///run/user/1000/podman/podman.sock
DOCKER_BUILDKIT=0          # use podman/buildah, not containerized BuildKit
COMPOSE_DOCKER_CLI_BUILD=0
```
BuildKit is disabled because compose otherwise runs `moby/buildkit` in a
container, which has no access to the host trust store and so cannot verify the
**BEV Issuing CA** that signs `docker2.bev.gv.at`. Podman builds on the host and
uses `/etc/pki/ca-trust` directly. Verified `RUN --mount=type=cache` (used 5
times across puko, default_backend, egisy-java) still works through buildah.

Note: the BEV CAs were never in `/etc/docker` — they are system trust anchors
(`BEV Root CA`, `BEV Issuing CA-01`), so removing `/etc/docker` cost nothing.
