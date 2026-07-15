# Kickstart for a scripted rheniite install — the documented install path.
#
# Why this exists: the interactive Zirconium/Anaconda ISO creates the primary
# user with HOME=/home/<user> (the symlinked spelling) instead of the atomic
# convention /var/home/<user>, which breaks path-canonicalising software like
# Synology Drive's Nautilus emblems (see backlog/var-home-passwd.md). Declaring
# the user here pins the homedir explicitly — and installs rheniite directly,
# skipping the Zirconium-then-rebase two-step. The image's fix-var-home guard
# would repair an interactive install too; this file just makes installs
# deterministic instead of self-healing.
#
# How to use: boot a Fedora/Zirconium installer ISO with this file appended:
#   inst.ks=hd:LABEL=KSDRIVE:/rheniite.ks    (kickstart on a second USB stick)
#   inst.ks=http://<host>/rheniite.ks        (served over the network)
#
# Before using:
#   1. Replace PASSWORD_HASH below — generate with:  openssl passwd -6
#   2. Review the disk section: clearpart WIPES the target disk.

text
lang en_US.UTF-8
keyboard us
timezone Europe/Amsterdam --utc

# Disk — destroys whatever is on the default target disk. Adjust per machine
# (e.g. add `ignoredisk --only-use=nvme0n1` to pin the target explicitly).
zerombr
clearpart --all --initlabel --disklabel gpt
autopart

# Install rheniite straight from the registry. Signature verification is
# skipped during install only: the installer environment doesn't carry the
# image's sigstore policy. The installed system does (reinier.pub +
# registries.d, baked in the Containerfile), so every update from the first
# `bootc upgrade` on IS verified.
ostreecontainer --url=ghcr.io/reinier/rheniite:latest --transport=registry --no-signature-verification

# The account, with the canonical homedir spelled out — the whole point.
rootpw --lock
user --name=reinierladan --gecos="Reinier Ladan" --groups=wheel --homedir=/var/home/reinierladan --iscrypted --password=PASSWORD_HASH

reboot
