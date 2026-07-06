# Personal bootc image layered on top of the Zirconium base.
# The base is the pristine fork's published image, so rebuilds pick up new bases.
FROM ghcr.io/reinier/zirconium:latest

# --- Web browsers (native RPMs) ---
# Native (non-Flatpak) browsers integrate with 1Password through the standard
# system native-messaging manifests and pass its browser verification with no
# per-app wrappers, D-Bus overrides, or custom_allowed_browsers entries.
# 1Password itself is intentionally NOT baked in here — it's run via distrobox
# instead (its export feature works there, unlike the RPM build).
RUN dnf5 -y install firefox chromium \
 && dnf5 clean all

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
