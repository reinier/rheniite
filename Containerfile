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
# Fedora's chromium now links the SYSTEM ffmpeg (libavcodec), which ships as
# ffmpeg-free with H.264/AAC stripped — breaking Teams WebRTC video and <video>
# mp4 playback. RPM Fusion's libavcodec-freeworld adds those proprietary codecs
# alongside the base ffmpeg-free (additive — no base-package swap or --allowerasing);
# Fedora's native chromium then picks them up, preserving 1Password native-messaging
# and the chrome-* app_ids used by niri window-rules / dank-lader.
# (RPM Fusion retired the chromium-freeworld and chromium-libs-media-freeworld
# packages once chromium switched to the system ffmpeg — libavcodec-freeworld
# supersedes both.) It lives in the free repo, so only that release is added.
RUN dnf5 -y install \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
 && dnf5 -y install firefox chromium libavcodec-freeworld \
 && rm -f /etc/yum.repos.d/rpmfusion-*.repo \
 && dnf5 clean all

# --- Nextcloud (native sync client + Nautilus integration) ---
# Native RPM instead of the Flatpak, so nextcloud-client-nautilus can hook GNOME
# Files for sync-status emblems + share actions — which a sandboxed Flatpak can't.
# The dotfiles autostart `nextcloud --background` and no longer ship the Flatpak
# single-instance-lock wrapper (that was only needed for DMS<->GNOME switching).
RUN dnf5 -y install nextcloud-client nextcloud-client-nautilus \
 && dnf5 clean all

# --- Synology Drive (native sync client + Nautilus integration) ---
# Unofficial RPM repack of Synology's official client, from the
# emixampp/synology-drive COPR (github.com/EmixamPP/synology-drive) — cleaner
# than an alien-converted deb or the Flatpak. The -noextra variant still ships
# the Nautilus extension (sync emblems + share menu, coexists with the
# Nextcloud one above), but drops the GNOME-Shell-only weak deps
# (gnome-shell-extension-appindicator) that are dead weight on niri, where DMS
# already provides the SNI tray for the status icon.
#
# The RPM puts its whole payload in /opt/Synology, but on a bootc image /opt
# is a symlink to var/opt, and rpm's hardened unpacker refuses to create
# package-owned directories through a symlink — the install aborts with
# "cpio: mkdir failed - File exists". So: swap /opt for a real directory just
# for the transaction, then relocate the payload into /usr (shipped + updated
# with the image — under the symlink it would land in machine-local /var,
# which materializes only on a first deployment and never updates), and
# restore the symlink exactly as the base had it (readlink fails the build
# loudly if a future base stops symlinking /opt; rmdir guards that nothing
# else was left behind in /opt). The tmpfiles.d drop-in recreates the
# expected /var/opt/Synology path at boot as a symlink back into /usr.
COPY synology-drive.repo /etc/yum.repos.d/synology-drive.repo
RUN opt_link="$(readlink /opt)" \
 && rm /opt && mkdir /opt \
 && dnf5 -y install synology-drive-noextra \
 && rm -f /etc/yum.repos.d/synology-drive.repo \
 && mkdir -p /usr/lib/opt \
 && mv /opt/Synology /usr/lib/opt/Synology \
 && rmdir /opt \
 && ln -s "$opt_link" /opt \
 && dnf5 clean all
COPY files/synology-drive-opt.conf /usr/lib/tmpfiles.d/synology-drive-opt.conf

# --- 1Password (desktop app + CLI) ---
# 1Password 8.12.28 moved the desktop app's payload (back) to /opt/1Password
# — 8.12.26 and earlier installed entirely under /usr — so it now needs the
# same /opt treatment as Synology Drive above: swap the symlink for a real
# directory so rpm can unpack, relocate the payload into /usr, restore the
# symlink, and let the tmpfiles.d drop-in provide /opt/1Password at runtime.
# The setgid/setuid bits below are required even with native browsers:
# BrowserSupport fails its own integrity check ("running without libc's
# security") without setgid, and chrome-sandbox needs setuid for the Electron
# sandbox. aarch64 ships only the CLI (no desktop app), so this image is
# x86_64.
COPY 1password.repo /etc/yum.repos.d/1password.repo
RUN rpm --import https://downloads.1password.com/linux/keys/1password.asc \
 && opt_link="$(readlink /opt)" \
 && rm /opt && mkdir /opt \
 # 8.12.28's %post mkdir -p's under /usr/local, which here is a dangling
 # symlink into var/usrlocal during the build (mkdir -p then fails with
 # "File exists"). Materialize the target so the scriptlet succeeds; what it
 # writes there is machine-local convenience, not needed by the app itself.
 && mkdir -p "$(realpath -m /usr/local)" \
 && dnf5 -y install 1password 1password-cli \
 && rm -f /etc/yum.repos.d/1password.repo \
 && mkdir -p /usr/lib/opt \
 && mv /opt/1Password /usr/lib/opt/1Password \
 && rmdir /opt \
 && ln -s "$opt_link" /opt \
 # Create onepassword / onepassword-cli now, so we can bake the setgid bits
 # into /usr — which is read-only at runtime.
 && systemd-sysusers \
 # chrome-sandbox: setuid root (Electron sandbox, electron/electron#17972).
 && chmod 4755 /usr/lib/opt/1Password/chrome-sandbox \
 # BrowserSupport: setgid onepassword (browser-extension <-> desktop-app link).
 && chgrp onepassword /usr/lib/opt/1Password/1Password-BrowserSupport \
 && chmod 2755 /usr/lib/opt/1Password/1Password-BrowserSupport \
 # op: setgid onepassword-cli (CLI <-> desktop-app link and SSH agent).
 && chgrp onepassword-cli /usr/bin/op \
 && chmod 2755 /usr/bin/op \
 && dnf5 clean all
COPY files/1password-opt.conf /usr/lib/tmpfiles.d/1password-opt.conf

# --- 1Password file pickers (export/import/attach) ---
# 1Password's hardened runtime needs restricted ptrace, or its portal file
# pickers silently no-op (this is what broke 1PUX export). See the drop-in.
COPY files/60-1password-ptrace.conf /usr/lib/sysctl.d/60-1password-ptrace.conf

# --- CLI toolkit (moved off Homebrew in dotfiles-rheniite) ---
# fish / eza / bat / jq / zip / fuse-sshfs from Fedora main; starship / lazygit / yazi
# from Terra (already enabled by the base's terra-release). Baking these means they're
# present at boot and update with the image instead of via a per-user `brew install`.
# fuse-sshfs is the Fedora package name for the sshfs FUSE filesystem (mount remote
# hosts over SSH); the `sshfs` command ships inside it.
RUN dnf5 -y install \
      fish eza bat jq zip fuse-sshfs \
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

# --- Printer management GUI (standalone; no GNOME Control Center on niri) ---
# CUPS itself comes from the base (socket-activated cups.socket). The DMS printer
# panel routes through the dms backend's "cups" capability, which this image's
# backend doesn't advertise — so this ships a self-contained GTK tool instead.
# system-config-printer drives CUPS via the cups-pk-helper polkit mechanism, so a
# wheel user adds/removes printers with their own password (no root, no CUPS
# SystemGroup membership). avahi/nss-mdns aren't added here: the base already
# provides mDNS discovery (a WiFi printer is found out of the box), and driverless
# dnssd:// queues resolve through libavahi at print time, not NSS.
RUN dnf5 -y install system-config-printer \
 && dnf5 clean all

# --- keyd (the tap-hold Super key) ---
# Built from source in the keyd-build stage above (pinned tag, no third-party COPR).
# Copy in just the artifacts — binary, systemd unit, man pages — so the toolchain
# never ships. Enablement + the personal mapping live in dotfiles-rheniite.
COPY --from=keyd-build /out/ /

# --- /var/home passwd guard (first-boot repair for an installer deviation) ---
# The Zirconium Anaconda ISO creates the primary user with HOME=/home/<user>
# (the symlinked spelling) instead of the atomic convention /var/home/<user>,
# even though this image's useradd default is already /var/home. Both spell
# the same directory, but path-canonicalising software that string-compares
# breaks on the mismatch — Synology Drive's Nautilus sync emblems were the
# first casualty. This oneshot rewrites any such passwd entry before user
# logins are allowed (so usermod never races a session), making installs from
# the GUI ISO self-healing on first boot. Details + the upstream report for
# the ISO itself: backlog/var-home-passwd.md.
COPY files/fix-var-home /usr/libexec/fix-var-home
COPY files/fix-var-home.service /usr/lib/systemd/system/fix-var-home.service
RUN chmod 0755 /usr/libexec/fix-var-home \
 && systemctl enable fix-var-home.service

# --- System defaults (first-boot setup that shouldn't need interactive sudo) ---
# Timezone baked in so a fresh install has the right clock without a `sudo
# timedatectl` step mid-`chezmoi apply` (which prompts for a password late in a
# long apply and times out if you've stepped away). Overridable per machine with
# `timedatectl set-timezone`. NTP/chronyd is already enabled by the base.
RUN ln -sf ../usr/share/zoneinfo/Europe/Amsterdam /etc/localtime

# Enable tailscaled so the daemon runs from boot. Without this its socket doesn't
# exist and the dotfiles' `tailscale set --operator` fails ("tailscaled.service not
# running"). Enabling it here leaves only the interactive `tailscale up` to you.
RUN systemctl enable tailscaled.service

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
