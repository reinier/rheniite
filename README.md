# rheniite

A personal [bootc](https://bootc-dev.github.io/bootc/) image built on top of
[Zirconium](https://github.com/reinier/zirconium) (`ghcr.io/reinier/zirconium`).

Zirconium is the base OS — a fork I control and rebuild. **rheniite** is the
declarative layer on top that adds my extra software and config.

## Install / rebase

```
sudo bootc switch ghcr.io/reinier/rheniite:latest
```

## What it adds

- **Web browsers** (native RPMs): `firefox` and `chromium`.

Native browsers integrate with 1Password using the standard system
native-messaging manifests and pass its browser verification with no wrappers,
D-Bus overrides, or `custom_allowed_browsers` entries.

## 1Password

1Password is **not** baked into the image. The RPM build's export feature is
broken, so 1Password runs via **distrobox** instead (where export works), and
integrates with the native browsers above.

> Earlier revisions baked the 1Password RPM in and bridged it to Flatpak browsers
> (setgid `BrowserSupport` + `flatpak-session-helper` + a per-user login service).
> See git history if that approach is ever needed again.

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
Zirconium base images). The image is built for **x86_64**.
