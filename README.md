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
  - Flatpak browser integration (`flatpak-session-helper`)

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
