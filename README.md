# rheniite

A personal [bootc](https://bootc-dev.github.io/bootc/) image built on top of
[Zirconium](https://github.com/zirconium-dev/zirconium)
(`ghcr.io/zirconium-dev/zirconium`).

Zirconium is the base OS — the official upstream image. **rheniite** is the
declarative layer on top that adds my extra software and config.

> I keep a personal fork at `ghcr.io/reinier/zirconium` as a fallback: if an
> upstream Zirconium update ever regresses, I can point the `FROM` in the
> `Containerfile` back at the fork (a base I know builds and boots) until
> upstream is fixed.

## Install / rebase

```
sudo bootc switch ghcr.io/reinier/rheniite:latest
```

## What it adds

- **Web browsers** (native RPMs): `firefox` and `chromium`.
- **Nextcloud** desktop sync client (`nextcloud-client`) + `nextcloud-client-nautilus`
  for GNOME Files sync-status emblems / share actions — native, not Flatpak.
- **Synology Drive** sync client (`synology-drive-noextra`, from the
  [emixampp/synology-drive](https://github.com/EmixamPP/synology-drive) COPR) with
  its Nautilus extension. The `/opt/Synology` payload is relocated into `/usr` so it
  ships/updates with the image; a `tmpfiles.d` drop-in restores the `/opt` path at
  boot (see `backlog/synology-drive.md` for the reasoning and rollback plan).
- **1Password** desktop app + `op` CLI (official RPM):
  - `onepassword` / `onepassword-cli` groups via the RPM's own `sysusers.d`
  - setuid/setgid bits baked into `/usr` (`chrome-sandbox`,
    `1Password-BrowserSupport`, `op`) — required for its integrity checks
- **`kernel.yama.ptrace_scope = 1`** (a `sysctl.d` drop-in) — see below.
- **CLI toolkit**: `fish`, `starship`, `eza`, `bat`, `jq`, `zip`, `lazygit`, `yazi`
  (Fedora main + Terra). Moved here off the per-user Homebrew install the dotfiles
  used to do on first apply.
- **VSCodium** (`codium`) from its official RPM repo — native, so the integrated
  terminal is the real host shell (brew tools / `op` / podman / distrobox on PATH).
- **Kitty** (`kitty`) — GPU-accelerated terminal, from Fedora main.
- **keyd** — the tap-hold Super key. Built from source (pinned tag) in a throwaway
  stage; only the artifacts ship. The personal mapping + `keyd.service` enablement
  live in the [dotfiles](https://forge.personalos.nl/reinierladan/dotfiles-rheniite).

## 1Password + browsers

The **native** `firefox`/`chromium` above integrate with 1Password through the
standard system native-messaging manifests and pass its browser verification —
no wrappers, D-Bus overrides, or `custom_allowed_browsers` entries needed.

1Password's file pickers (1PUX **export**, import, file attachment, item icons)
rely on a hardened runtime that validates its `xdg-desktop-portal` FileChooser
peer via `/proc/<pid>/root`. With `kernel.yama.ptrace_scope=0` (the previous
default) that access is denied and every picker **silently no-ops** — no dialog,
no error. Setting `ptrace_scope=1` fixes it; it's also the Debian/Ubuntu/Arch
default and a security hardening. That's why 1PUX export was broken before.

> Earlier revisions ran 1Password via distrobox/Homebrew to work around the
> broken export, and bridged the RPM build to *Flatpak* browsers (setgid
> `BrowserSupport` + `flatpak-session-helper` + a per-user login service). Both
> are obsolete now that the root cause (ptrace_scope) is fixed and browsers are
> native. See git history if ever needed again.

## Signed updates

CI signs the pushed image with a sigstore key (the `SIGNING_SECRET` repo secret).
The image bakes the matching public key (`reinier.pub`) and a `policy.json` entry
that requires a valid signature for the `ghcr.io/reinier` namespace, so a running
system verifies its own `bootc` updates.

> Because the baked policy **requires** a signature, an unsigned push (missing
> `SIGNING_SECRET`) would be rejected by `bootc switch`. Keep the secret set.

## How it builds

`Containerfile` does `FROM ghcr.io/zirconium-dev/zirconium:latest` and layers the
above. CI rebuilds on pushes to `main`, on PRs, and daily (to pick up new
Zirconium base images). The image is built for **x86_64**.
