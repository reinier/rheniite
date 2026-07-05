# Personal bootc image layered on top of the Zirconium base.
# The base is the pristine fork's published image, so rebuilds pick up new bases.
FROM ghcr.io/reinier/zirconium:latest

# --- 1Password (desktop app + CLI) ---
# The modern 1Password RPM installs entirely under /usr and ships its own
# sysusers.d for the onepassword / onepassword-cli groups. Its aarch64 repo ships
# only the CLI (no desktop app), so this image targets x86_64.
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
 # Let Flatpak-packaged browsers reach the desktop app for the extension.
 && printf '\nflatpak-session-helper\n' >> /etc/1password/custom_allowed_browsers

# --- Image-update trust ---
# rheniite is what this machine boots, so it must verify its own update stream
# (ghcr.io/reinier/rheniite) rather than inherit that trust from the base — the
# pristine zirconium fork only bakes upstream's policy. Install reinier's public
# signing key and add a sigstoreSigned entry for the ghcr.io/reinier namespace.
# CI signs the pushed image with the matching private key (SIGNING_SECRET).
COPY reinier.pub /usr/share/pki/containers/reinier.pub
COPY patch-policy.py /tmp/patch-policy.py
RUN python3 /tmp/patch-policy.py && rm -f /tmp/patch-policy.py

# Fail the build on real bootc issues (warnings are fine).
RUN bootc container lint
