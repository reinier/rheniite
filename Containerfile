# Personal bootc image layered on top of the Zirconium base.
# The base is the pristine fork's published image, so rebuilds pick up new bases.
FROM ghcr.io/reinier/zirconium:latest

# --- Web browsers (native RPMs) ---
# Native (non-Flatpak) browsers integrate with 1Password through the standard
# system native-messaging manifests and pass its browser verification with no
# per-app wrappers, D-Bus overrides, or custom_allowed_browsers entries.
RUN dnf5 -y install firefox chromium \
 && dnf5 clean all

# --- 1Password (desktop app + CLI) ---
# The modern 1Password RPM installs entirely under /usr and ships its own
# sysusers.d for the onepassword / onepassword-cli groups. The setgid/setuid
# bits below are required even with native browsers: BrowserSupport fails its
# own integrity check ("running without libc's security") without setgid, and
# chrome-sandbox needs setuid for the Electron sandbox. aarch64 ships only the
# CLI (no desktop app), so this image is x86_64.
COPY 1password.repo /etc/yum.repos.d/1password.repo
RUN rpm --import https://downloads.1password.com/linux/keys/1password.asc \
 && dnf5 -y install 1password 1password-cli \
 && rm -f /etc/yum.repos.d/1password.repo \
 # Create onepassword / onepassword-cli (from the RPM's sysusers.d) now, so we
 # can bake the setgid bits into /usr — which is read-only at runtime.
 && systemd-sysusers \
 # chrome-sandbox: setuid root (Electron sandbox, electron/electron#17972).
 && chmod 4755 /usr/share/1password/chrome-sandbox \
 # BrowserSupport: setgid onepassword (browser-extension <-> desktop-app link).
 && chgrp onepassword /usr/libexec/1Password-BrowserSupport \
 && chmod 2755 /usr/libexec/1Password-BrowserSupport \
 # op: setgid onepassword-cli (CLI <-> desktop-app link and SSH agent).
 && chgrp onepassword-cli /usr/bin/op \
 && chmod 2755 /usr/bin/op \
 && dnf5 clean all

# --- 1Password file pickers (export/import/attach) ---
# 1Password's hardened runtime needs restricted ptrace, or its portal file
# pickers silently no-op (this is what broke 1PUX export). See the drop-in.
COPY files/60-1password-ptrace.conf /usr/lib/sysctl.d/60-1password-ptrace.conf

# --- Image-update trust ---
# rheniite is what this machine boots, so it must verify its own update stream
# (ghcr.io/reinier/rheniite) rather than inherit that trust from the base — the
# pristine zirconium fork only bakes upstream's policy. Install reinier's public
# signing key and add a sigstoreSigned entry for the ghcr.io/reinier namespace.
# CI signs the pushed image with the matching private key (SIGNING_SECRET).
COPY reinier.pub /usr/share/pki/containers/reinier.pub
COPY patch-policy.py /tmp/patch-policy.py
RUN python3 /tmp/patch-policy.py && rm -f /tmp/patch-policy.py

# sigstoreSigned above only takes effect if the reader is told to fetch sigstore
# *attachment* signatures for this namespace — otherwise verification looks in the
# wrong place and fails with "a signature was required, but no signature exists".
# The base ships this only for ghcr.io/zirconium-dev, so add ghcr.io/reinier.
# Written to both the factory template and /etc (whichever the system reads).
COPY files/reinier-registries.yaml /usr/share/factory/etc/containers/registries.d/reinier.yaml
RUN mkdir -p /etc/containers/registries.d \
 && cp /usr/share/factory/etc/containers/registries.d/reinier.yaml \
       /etc/containers/registries.d/reinier.yaml

# Fail the build on real bootc issues (warnings are fine).
RUN bootc container lint
