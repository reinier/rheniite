# rheniite

A personal [bootc](https://bootc-dev.github.io/bootc/) image built on top of
[Zirconium](https://github.com/reinier/zirconium) (`ghcr.io/reinier/zirconium`).

Zirconium is the base OS — a fork I control and rebuild. **rheniite** is the
declarative layer on top that adds my extra software and config, currently
1Password (desktop app + CLI).

## Install / rebase

```
sudo bootc switch ghcr.io/reinier/rheniite:latest
```

## What it adds

- **1Password** desktop app + `op` CLI, set up for atomic/bootc:
  - installed from the official 1Password RPM repo
  - `onepassword` / `onepassword-cli` groups via the RPM's own `sysusers.d`
  - the setuid/setgid bits baked into `/usr` (`chrome-sandbox`,
    `1Password-BrowserSupport`, `op`)
  - **Flatpak browser integration**, fully automatic (see below)

## Flatpak browser integration

1Password officially [doesn't support](https://support.1password.com/connect-1password-browser-app/)
talking to a Flatpak-packaged browser: the desktop app can't reach a sandboxed
browser's native-messaging host, and the browser can't exec the host helper. The
host-side half is baked into the image (`1Password-BrowserSupport` is setgid, and
`flatpak-session-helper` is in `/etc/1password/custom_allowed_browsers`). The
per-user half can't live in the read-only image, so a systemd **user** service
(`1password-flatpak-setup.service`, enabled for all users) runs at login and, for
every installed Flatpak browser, writes into its `~/.var/app/<id>` sandbox:

- a `flatpak-spawn --host …/1Password-BrowserSupport` wrapper,
- a `com.1password.1password` native-messaging manifest pointing at it, and
- a `--talk-name=org.freedesktop.Flatpak` override.

Just install a browser as Flatpak and log in again (or `systemctl --user start
1password-flatpak-setup`); then fully quit and reopen the browser. Supported
browsers are listed in `files/1password-flatpak-setup` — add app-ids there for
others.

> ⚠️ **Security trade-off:** `flatpak-session-helper` in `custom_allowed_browsers`
> is the only way 1Password can accept a Flatpak connection (it only ever sees
> that helper, not the real browser), and it whitelists **every** Flatpak app to
> 1Password — not just browsers. This is inherent to the workaround.

## Signed updates

CI signs the pushed image with a sigstore key (the `SIGNING_SECRET` repo secret).
The image bakes the matching public key (`reinier.pub`) and a `policy.json` entry
that requires a valid signature for the `ghcr.io/reinier` namespace, so a running
system verifies its own `bootc` updates.

> Because the baked policy **requires** a signature, an unsigned push (missing
> `SIGNING_SECRET`) would be rejected by `bootc switch`. Keep the secret set.

## How it builds

`Containerfile` does `FROM ghcr.io/reinier/zirconium:latest` and layers the
above. CI rebuilds on pushes to `main`, on PRs, and daily (to pick up new
Zirconium base images).

> **x86_64 only** — 1Password's aarch64 RPM repo ships only the CLI, not the
> desktop app.
