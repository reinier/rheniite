# 1Password 8.12.28 moved to /opt — relocate like Synology Drive

- **Status:** done (implemented on `claude/synology-drive-conflicts-qoj98k`)
- **Created:** 2026-07-14
- **Area:** image (Containerfile, `files/1password-opt.conf`)
- **Related:** PR #7 CI run 29339344097 (first failure);
  [backlog/synology-drive.md](synology-drive.md) (same mechanism, discovered
  first there)

## Problem

1Password released 8.12.28 on 2026-07-14; unlike 8.12.26 and earlier (which
installed entirely under `/usr`), it ships the desktop app's payload in
`/opt/1Password` — the classic 1Password Linux layout. On this bootc image
that fails twice over: rpm's hardened unpacker refuses to create package
directories through the `/opt -> var/opt` symlink (`cpio: mkdir failed - File
exists`, the same failure mode Synology Drive hit), and even if it unpacked,
`/var/opt` content wouldn't ship or update with the image.

This is an upstream packaging change, not something this repo did: **every**
image build after 1Password's stable repo served 8.12.28 fails, including
main's daily scheduled builds. The morning build of 2026-07-14 (04:51,
8.12.26) was the last green one; PR #7's build at 14:08 was simply the first
to pull 8.12.28.

## Fix

Same treatment as Synology Drive: swap `/opt` for a real directory for the
duration of the dnf transaction, `mv /opt/1Password /usr/lib/opt/1Password`,
restore the symlink verbatim, and add `files/1password-opt.conf` (tmpfiles.d)
recreating `/var/opt/1Password -> /usr/lib/opt/1Password` at boot.

The setuid/setgid baking moved with the payload: `chrome-sandbox` and
`1Password-BrowserSupport` are now chmod/chgrp'd at their
`/usr/lib/opt/1Password/` locations (they lived in `/usr/share/1password` and
`/usr/libexec` in the old layout). `op` is unchanged (`1password-cli` still
installs to `/usr/bin`).

## Second failure: %post vs the /usr/local symlink

With the /opt swap in place the payload unpacked fine, but 8.12.28's new
%post scriptlet failed the transaction (CI run 29339938148):

    >>> mkdir: cannot create directory '/usr/local': File exists

/usr/local is a symlink into `var/usrlocal` on this layout, and during a
container build the target doesn't exist — the symlink dangles, and the
scriptlet's `mkdir -p` under /usr/local trips over it. Fix: `mkdir -p
"$(realpath -m /usr/local)"` before the install so the scriptlet has a real
directory to write into. Whatever it puts there lands in machine-local
`/var/usrlocal` (first-boot template) — convenience files, not something the
app needs from the image.

## Open assumptions (CI verifies)

Authored blind — the network policy of the authoring environment blocks
`downloads.1password.com`, so the 8.12.28 layout is inferred from the failure
log (`/opt/1Password/1Password-BrowserSupport`) and 1Password's classic
pre-/usr layout. If CI still fails, likely suspects: a hybrid layout keeping
some binaries under `/usr`, or the `sysusers.d` groups file having moved/been
replaced by scriptlets (the `chgrp onepassword` would then fail loudly).

## Rollback / upstream watch

If a later 1Password release moves back under `/usr`, the build fails loudly
at the `mv /opt/1Password` step — then revert this item's Containerfile block
to the pre-8.12.28 shape (see git history) and drop
`files/1password-opt.conf`. Machine-local leftover on rollback: the dangling
`/var/opt/1Password` symlink.
