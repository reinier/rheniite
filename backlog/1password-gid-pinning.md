# 1Password: pin the onepassword/onepassword-cli GIDs

- **Status:** in-progress (fix on `claude/1password-gid-pinning`; verify on
  the machine after the next `bootc upgrade`)
- **Created:** 2026-07-15
- **Area:** image (Containerfile, 1Password section)
- **Related:** [1password-opt-layout.md](1password-opt-layout.md) (the
  relocation this bug shipped alongside)

## Problem

After the 8.12.28 `/opt` relocation landed, the 1Password browser extension
could no longer connect to the desktop app. BrowserSupport's log names the
failure precisely:

    WARN  binary permission verification failed for /usr/lib/opt/1Password/1Password-BrowserSupport
    ERROR Browser support error: BrowserProcessVerification(BinaryPermissions)

Root cause is GID drift, not the relocation itself. The build ran
`systemd-sysusers` and let it allocate the group IDs dynamically, then baked
`chgrp onepassword` + setgid into `/usr`. File group ownership ships as a raw
number, but `/etc/group` is machine-local state that bootc never rewrites —
so the number baked at build time and the number the machine maps the group
name to can disagree. On this laptop (whose `/etc/group` predates rheniite —
migrated from Bluefin):

| | build baked | machine `/etc/group` | result |
|---|---|---|---|
| `1Password-BrowserSupport` | gid 5014 | `onepassword` = 5010 | group `UNKNOWN` → verification fails, browser link dead |
| `op` | gid 5013 | `onepassword-cli` = 5013 | match by pure luck → CLI/SSH-agent kept working |
| `chrome-sandbox` | 0:0 setuid | n/a | unaffected (no group involved) |

The lucky `op` match is what made the breakage look partial and confusing.
(Same day, unrelated: the DMS settings reset was a DMS shutdown race, and the
`/var/home` passwd migration was innocent of both — see
[var-home-passwd.md](var-home-passwd.md).)

## Fix

Create both groups with **pinned GIDs before `dnf5 install`** in the
1Password build step (`groupadd -g 5010 onepassword`,
`groupadd -g 5013 onepassword-cli`), replacing the unpinned
`systemd-sysusers` call. Pinned values are the ones this machine's
`/etc/group` already carries, so:

- the baked setgid binaries resolve correctly on this machine with **no
  machine-side migration at all**, and
- fresh installs inherit the same numbers via the image's `/etc` default, so
  build and machine can never drift again.

If the RPM's scriptlets try to create the groups themselves, they find them
already present and no-op.

## Verification

- CI: build green (groupadd would fail loudly on a GID collision in the
  base image), `bootc container lint` green.
- Machine, after `bootc upgrade` + reboot:
  `stat -c '%a %u:%g %U:%G' /usr/lib/opt/1Password/1Password-BrowserSupport`
  → `2755 0:5010 root:onepassword`; browser extension connects; `op` still
  works; no new BinaryPermissions errors in
  `~/.config/1Password/logs/BrowserSupport/`.

## Rollback

Revert the commit — the next build goes back to dynamic allocation (and the
broken browser link on this machine). No machine-local state to undo; the
machine's `/etc/group` is untouched throughout.
