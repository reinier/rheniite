# Synology Drive: native sync client in the image

- **Status:** done (implemented on `claude/synology-drive-conflicts-qoj98k`)
- **Created:** 2026-07-14
- **Area:** image (Containerfile, `synology-drive.repo`, `files/synology-drive-opt.conf`)
- **Related:** <https://github.com/EmixamPP/synology-drive> (spec files + COPR),
  COPR `emixampp/synology-drive`

## Problem

Want the Synology Drive Client on rheniite, ideally native (not Flatpak) so the
Nautilus integration works like the Nextcloud one. Synology only ships a deb;
the usual routes are an alien-converted deb, the Flatpak (no Nautilus hooks), or
EmixamPP's unofficial RPM repack. The RPM is the right shape for this image,
**but** it installs its entire payload into `/opt/Synology`, and on a bootc
image `/opt` is a symlink into `/var` — machine-local state that materializes
only on a *first* deployment. Installed naively, the app would never appear on a
rebase of an already-deployed machine and would never receive image updates.

## Options

1. **Flatpak (per-user, dotfiles concern)** — sandboxed, so no Nautilus
   sync-status emblems / share menu; the upstream README exists precisely
   because the Flatpak is limited. Rejected.
2. **`synology-drive` (full variant) from the COPR** — same payload, but its
   weak deps (`gnome-shell-extension-appindicator`) target GNOME Shell; dead
   weight on niri where DMS already provides an SNI tray. dnf5 installs weak
   deps by default. Rejected.
3. **`synology-drive-noextra` + `/opt` relocation** *(chosen)* — the noextra
   variant still ships the Nautilus extension into `%{_libdir}` (the path
   Fedora's Nautilus actually scans) and only drops the GNOME-Shell Recommends.
   Relocate the payload to `/usr/lib/opt/Synology` at build time and restore
   `/var/opt/Synology` as a symlink at boot via `tmpfiles.d` (the pattern
   Universal Blue images use for `/opt`-based RPMs).

Conflict check (why this is safe to add): all installed paths are the package's
own; the only RPM `Conflicts:` is between the two variants themselves. Nautilus
loads multiple extensions side by side, so it coexists with
`nextcloud-client-nautilus`. Upstream's only conflict warning (previous
alien/Flatpak installs) doesn't apply to an image build. It does hard-require
`gtk2`, which Fedora still packages but has long wanted to retire — if a future
base drops it, the image build fails loudly at the `dnf5 install` step.

## Implementation

- `synology-drive.repo` — COPR repo file (gpgcheck against the COPR project
  key), added before and removed after the install like the 1Password/VSCodium
  repos.
- Containerfile: `dnf5 -y install synology-drive-noextra`, then
  `mv /opt/Synology /usr/lib/opt/Synology` (the `mv` resolves through the
  `/opt -> var/opt` symlink during the build).
- `files/synology-drive-opt.conf` → `/usr/lib/tmpfiles.d/`: recreates
  `/var/opt/Synology -> /usr/lib/opt/Synology` at boot (`L+`, so a stale
  first-boot copy from an older build can't shadow the shipped payload).

Autostart/config is a dotfiles-rheniite concern, same as `nextcloud
--background`.

## Verification

- CI (PR build) proves the COPR has a fedora-44 chroot, `gtk2` resolves, and
  `bootc container lint` stays green. (Build-time network to COPR is blocked in
  the authoring environment, so CI is the first real end-to-end check.)
- On the machine after `bootc upgrade`: `ls -l /var/opt/Synology` shows the
  symlink into `/usr/lib/opt/Synology`; `synology-drive` launches; GNOME Files
  shows Synology emblems alongside Nextcloud's.

## Rollback

This is a trial. To undo:

1. Revert the implementing commit (or just don't merge the PR); the next image
   build no longer contains the app. `bootc rollback` flips back to the
   previous deployment immediately if needed before that build lands.
2. Machine-local leftovers to clean by hand (the image can't remove them):
   `~/.SynologyDrive` (user data/logs) and the now-dangling
   `/var/opt/Synology` symlink.
