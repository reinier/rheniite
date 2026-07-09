# --- keyd: build from source, pinned to an upstream release tag ---
# Built in a throwaway stage so the toolchain (git/make/gcc) never ships in the
# final image — only the artifacts are COPYed in below. Builder is fedora:44 to
# match the base's Fedora release, so the compiled binary is ABI-compatible.
# Bump KEYD_VERSION deliberately on new upstream releases.
#
# FORCE_SYSTEMD=1 is required: keyd's Makefile only installs keyd.service when
# /run/systemd/system exists (or FORCE_SYSTEMD is set). There's no running
# systemd inside a container build stage, so without it the unit is silently
# skipped, never lands in /out, and the final image ships the binary but no
# service — leaving `keyd.service does not exist` at runtime.
FROM registry.fedoraproject.org/fedora:44 AS keyd-build
ARG KEYD_VERSION=v2.6.0
RUN dnf5 -y install git make gcc kernel-headers \
 && git clone --depth 1 --branch "$KEYD_VERSION" https://github.com/rvaiya/keyd /src \
 && make -C /src PREFIX=/usr \
 && make -C /src PREFIX=/usr DESTDIR=/out FORCE_SYSTEMD=1 install

# Personal bootc image layered on top of the Zirconium base.
# The base is the official upstream Zirconium image, so rebuilds pick up new
# bases. (A personal fork at ghcr.io/reinier/zirconium is kept as a fallback for
# when an upstream update regresses — swap the FROM back to it if ever needed.)
FROM ghcr.io/zirconium-dev/zirconium:latest

# --- Web browsers (native RPMs) ---
# Native (non-Flatpak) browsers integrate with 1Password through the standard
# system native-messaging manifests and pass its browser verification with no
# per-app wrappers, D-Bus overrides, or custom_allowed_browsers entries.
RUN dnf5 -y install firefox chromium \
 && dnf5 clean all

# --- Nextcloud (native sync client + Nautilus integration) ---
# Native RPM instead of the Flatpak, so nextcloud-client-nautilus can hook GNOME
# Files for sync-status emblems + share actions — which a sandboxed Flatpak can't.
# The dotfiles autostart `nextcloud --background` and no longer ship the Flatpak
# single-instance-lock wrapper (that was only needed for DMS<->GNOME switching).
RUN dnf5 -y install nextcloud-client nextcloud-client-nautilus \
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

# --- CLI toolkit (moved off Homebrew in dotfiles-rheniite) ---
# fish / eza / bat / jq / zip from Fedora main; starship / lazygit / yazi from Terra
# (already enabled by the base's terra-release). Baking these means they're present
# at boot and update with the image instead of via a per-user `brew install`.
RUN dnf5 -y install \
      fish eza bat jq zip \
      starship lazygit yazi \
 && dnf5 clean all

# --- VSCodium (native editor, from VSCodium's own RPM repo) ---
# Native (not Flatpak) so the integrated terminal is the real host shell with brew
# tools / op / podman / distrobox on PATH — the right fit for this dev-focused image.
# paulcarroty's repo is VSCodium's canonical RPM channel (see vscodium.com/install).
COPY vscodium.repo /etc/yum.repos.d/vscodium.repo
RUN dnf5 -y install codium \
 && rm -f /etc/yum.repos.d/vscodium.repo \
 && dnf5 clean all

# --- Kitty (GPU-accelerated terminal) ---
# From Fedora main. Pulls in kitty-terminfo so remote hosts resolve TERM=xterm-kitty.
RUN dnf5 -y install kitty \
 && dnf5 clean all

# --- keyd (the tap-hold Super key) ---
# Built from source in the keyd-build stage above (pinned tag, no third-party COPR).
# Copy in just the artifacts — binary, systemd unit, man pages — so the toolchain
# never ships. Enablement + the personal mapping live in dotfiles-rheniite.
COPY --from=keyd-build /out/ /

# --- Image-update trust ---
# rheniite is what this machine boots, so it must verify its own update stream
# (ghcr.io/reinier/rheniite) rather than inherit that trust from the base — the
# upstream zirconium base only bakes its own policy. Install reinier's public
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
