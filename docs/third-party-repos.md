# Third-party software sources

Everything rheniite installs that does **not** come from the official Fedora
repositories (Fedora main/updates), and how each source is wired in. Everything
else in the `Containerfile` — firefox, chromium, fish, eza, bat, jq, zip,
fuse-sshfs, kitty, system-config-printer — is plain Fedora main.

Two properties hold for every RPM source below:

- **No repo is left enabled in the final image.** Repo files are `COPY`d in,
  used for the one `dnf5 install`, then deleted — the booted system has no
  third-party repos configured. Updates arrive through image rebuilds (CI runs
  daily), which re-add the repo and pick up whatever is latest.
- **`gpgcheck=1` everywhere.** Every source's packages are verified against
  that vendor's published key at build time.

## Overview

| Source | What we take from it | Repo file | Left in image? |
|---|---|---|---|
| [RPM Fusion (free)](https://rpmfusion.org) | `libavcodec-freeworld` | release RPM from rpmfusion.org | no — removed after install |
| [Terra](https://terra.fyralabs.com) | `starship`, `lazygit`, `yazi` | `terra-release` (enabled by the Zirconium base) | yes — base's choice |
| [1Password](https://support.1password.com/install-linux/) | `1password`, `1password-cli` | `1password.repo` | no — removed after install |
| [VSCodium](https://vscodium.com/install/) | `codium` | `vscodium.repo` | no — removed after install |
| [COPR emixampp/synology-drive](https://github.com/EmixamPP/synology-drive) | `synology-drive-noextra` | `synology-drive.repo` | no — removed after install |
| [keyd](https://github.com/rvaiya/keyd) (source build) | `keyd` binary + unit + man pages | — (git clone, pinned tag) | artifacts only |

## RPM Fusion (free)

- **Provides:** `libavcodec-freeworld` — the proprietary H.264/AAC codecs that
  Fedora strips from `ffmpeg-free`. Fedora's native chromium links the system
  ffmpeg, so without this, Teams WebRTC video and `<video>` mp4 playback break.
- **Why not Fedora:** patent-encumbered codecs; Fedora cannot ship them.
- **Wiring:** the `rpmfusion-free-release-$(rpm -E %fedora)` RPM is installed
  straight from `mirrors.rpmfusion.org` (which also lands its GPG keys), used
  for the one install, then all `rpmfusion-*.repo` files are removed. Only the
  *free* repo is ever added — nothing from nonfree.

## Terra

- **Provides:** `starship`, `lazygit`, `yazi` (CLI toolkit pieces newer/absent
  in Fedora main).
- **Why not Fedora:** not packaged, or too old, in Fedora main.
- **Wiring:** the repo is **not** added by rheniite — the Zirconium base ships
  `terra-release` with the repo enabled, so it's also the one third-party RPM
  repo present (and trusted) on the running system. That's a base-image
  decision; if the base ever drops it, the `dnf5 install` in our CLI-toolkit
  layer fails loudly.

## 1Password

- **Provides:** `1password` (desktop app), `1password-cli` (`op`).
- **Why not Fedora:** proprietary; only distributed by 1Password themselves.
- **Wiring:** `1password.repo` → downloads.1password.com stable channel, key
  imported from `1password.asc` before install, repo removed afterwards. The
  Containerfile then bakes the required setuid/setgid bits into `/usr` (see the
  README's 1Password section for why).

## VSCodium

- **Provides:** `codium`.
- **Why not Fedora:** not packaged in Fedora; paulcarroty's repo is the
  canonical RPM channel per vscodium.com.
- **Wiring:** `vscodium.repo` → `paulcarroty.gitlab.io` RPM repo, with
  `repo_gpgcheck=1` on top of package gpgcheck; repo removed after install.

## COPR: emixampp/synology-drive

- **Provides:** `synology-drive-noextra` — an unofficial but clean RPM repack
  of Synology's official Drive client (Synology only ships a deb).
- **Why not Fedora:** proprietary Synology payload; can't be packaged by
  Fedora. This COPR is a third-party repack — the most "trust the maintainer"
  entry on this list. Spec files are public at
  [EmixamPP/synology-drive](https://github.com/EmixamPP/synology-drive).
- **Wiring:** `synology-drive.repo` → the COPR's fedora-`$releasever` chroot,
  gpgcheck against the COPR project key, repo removed after install. The `/opt`
  payload is relocated into `/usr` for bootc — see
  [`backlog/synology-drive.md`](backlog/synology-drive.md).

## keyd (built from source)

- **Provides:** the `keyd` daemon (tap-hold Super key), its systemd unit and
  man pages.
- **Why not Fedora:** not in Fedora main; the alternative would be a
  third-party COPR, and a pinned-tag source build was judged more trustworthy
  than tracking someone's COPR.
- **Wiring:** throwaway `fedora:44` build stage clones
  `github.com/rvaiya/keyd` at a pinned release tag (`KEYD_VERSION`), compiles,
  and only the installed artifacts are `COPY`d into the final image — the
  toolchain never ships. Version bumps are deliberate (edit the ARG).

## Related but not an RPM source

- **Base image:** `ghcr.io/zirconium-dev/zirconium:latest` — the whole OS
  underneath this layer, pulled fresh on every CI build and sigstore-verified
  on the machine per the policy baked by `patch-policy.py`. rheniite's own
  update stream (`ghcr.io/reinier/rheniite`) is likewise signed by CI and
  verified via `reinier.pub`.
