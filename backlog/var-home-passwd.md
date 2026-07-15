# /var/home passwd convention: guard + scripted install

- **Status:** in-progress (guard + kickstart implemented on
  `claude/github-build-failure-0n2idn`; machine migration and upstream report
  pending)
- **Created:** 2026-07-15
- **Area:** image (Containerfile, `files/fix-var-home*`), install
  (`install/rheniite.ks`)
- **Related:** [synology-drive.md](synology-drive.md) (the feature that exposed
  it), <https://github.com/zirconium-dev/zirconium> (installer ISO — upstream
  report to file)

## Problem

Synology Drive's sync-status emblems never appeared in Nautilus, while
Nextcloud's worked on the same files. No errors anywhere.

Root cause is a path-*spelling* mismatch, not a Synology bug per se. On
ostree/bootc systems `/home` is a symlink to `var/home`, so the same directory
has two spellings. The Fedora-atomic convention is that `/etc/passwd` carries
the canonical one (`/var/home/<user>`) — and this image's `/etc/default/useradd`
already says `HOME=/var/home`. But the **Zirconium Anaconda ISO creates the
primary user with an explicit `/home/<user>`**, bypassing that default. The
session then has `$HOME=/home/reinierladan`, Nautilus hands the extension
`/home/...` paths, while the Synology daemon registered the sync root
canonicalised (`/var/home/...` — confirmed: its sqlite DBs contain only that
form). The daemon's literal prefix match fails, every file reports "not
synced", no emblems. Nextcloud resolves paths properly and doesn't care.

Diagnosis was confirmed behaviourally: `nautilus /var/home/.../SynologyDrive`
shows emblems; `nautilus ~/SynologyDrive` (same directory, symlinked spelling)
doesn't.

Because the account is machine state, the image can't retroactively fix an
installed system by shipping files — `/etc/passwd` belongs to the machine, and
bootc upgrades deliberately never rewrite user records. The existing laptop
needs a one-time `usermod -d /var/home/reinierladan reinierladan` from a root
TTY (no `-m`: the data already lives there; `/home/...` strings keep resolving
through the symlink, so blast radius is limited to string-comparing consumers —
GTK bookmarks, Flatpak overrides).

## Options

1. **Document the manual fix only** — cheap, but every future install from the
   ISO reproduces the bug and relies on remembering this file. Kept as the
   fallback layer (README note), not the plan.
2. **First-boot guard service** *(chosen)* — a oneshot that rewrites any
   `1000 <= uid < 65534` passwd entry with a `/home/...` home (where
   `/var/home/<user>` exists) before `systemd-user-sessions.service` allows
   logins. No user processes exist that early, so `usermod` can't race a
   session; idempotent, matches nothing on a healthy system. The
   Universal Blue images use the same first-boot-repair pattern. Cost: ~20
   lines that touch `/etc/passwd` at boot forever, and it papers over the
   installer bug rather than fixing it (hence the upstream report below).
3. **Scripted install via kickstart** *(chosen)* — `install/rheniite.ks` pins
   `user --homedir=/var/home/...` explicitly and installs rheniite directly via
   `ostreecontainer` (no Zirconium-then-rebase step). Deterministic by
   construction; the guard then never has anything to do.
4. **bootc-image-builder** — flashable disk images with declared users;
   rejected as too much machinery for one laptop (and user-home support in its
   config needs verifying).
5. **Official Silverblue ISO, then `bootc switch`** — works (that ISO follows
   the convention) but is a two-step install with nothing pinned in this repo.

## Implementation

- `files/fix-var-home` → `/usr/libexec/fix-var-home`: the repair script (POSIX
  sh, reads `/etc/passwd` directly — local accounts only by design).
- `files/fix-var-home.service` → `/usr/lib/systemd/system/`: oneshot,
  `After=local-fs.target`, `Before=systemd-user-sessions.service`, enabled in
  the Containerfile.
- `install/rheniite.ks`: the documented install path (placeholder password
  hash; disk section reviewed per machine).

## Verification

- CI: `bootc container lint` stays green; unit enablement succeeds at build.
- On the machine after `bootc upgrade`: `systemctl status fix-var-home` ran
  and exited 0. (On this laptop the manual `usermod` migration will already
  have fixed the entry, so the guard should be a no-op — `getent passwd
  reinierladan` shows `/var/home/...` either way.)
- End-to-end (post-migration): `nautilus ~/SynologyDrive` shows sync emblems;
  Nextcloud emblems unaffected.
- On the *next* fresh install (kickstart or interactive): first boot lands
  with the canonical home with no manual step.

## Rollback

Revert the commit; the next image no longer ships the guard or kickstart. The
guard makes no destructive changes to roll back on the machine — it only ever
rewrites the passwd home field to the spelling the data already has. A
manually migrated machine can be reverted with
`usermod -d /home/reinierladan reinierladan` (pure string revert), though
there's no reason to.

## Upstream report (to file against Zirconium)

> **Anaconda ISO creates users with `/home/<user>` instead of `/var/home/<user>`**
>
> Users created by the Zirconium installer ISO get `HOME=/home/<user>` in
> `/etc/passwd` — the symlinked spelling — rather than the Fedora-atomic
> convention `/var/home/<user>` (which the image's own
> `/etc/default/useradd` correctly defaults to; the installer passes an
> explicit path that bypasses it). Both spellings resolve to the same
> directory, but software that canonicalises paths and string-compares
> breaks: e.g. Synology Drive's Nautilus sync emblems silently never render,
> because its daemon registers the sync root canonicalised and prefix-matches
> against the `$HOME`-derived paths Nautilus queries with. Official
> Silverblue installs carry the `/var/home` form. Could the ISO's user
> creation use `/var/home/<user>`?
