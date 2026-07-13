# Chromium with free codecs (H.264 for WebRTC / `<video>`)

- **Status:** done (Containerfile: stock `chromium` + RPM Fusion `libavcodec-freeworld`)
- **Created:** 2026-07-13
- **Area:** image (`Containerfile`)
- **Related:** Teams video was broken → worked around with the `teams_for_linux`
  Flatpak (dotfiles-rheniite `run_onchange_install-flatpaks.sh`). This item is the
  proper fix for *native* Chromium so the workaround can eventually be dropped.

## Resolution

Shipped as neither Option A nor B exactly. On Fedora 44 the codec story changed:
Fedora's `chromium` now links the **system** ffmpeg (`libavcodec`) instead of a
bundled copy (rhbz#2053867). As a result RPM Fusion **retired** both
`chromium-freeworld` and `chromium-libs-media-freeworld` — neither exists for f44
(the free repo ships no `chromium*` packages at all), so Option B as originally
written fails to build (`No match for argument`).

The working fix keeps stock `chromium` and adds **`libavcodec-freeworld`** from
RPM Fusion free. It supplies H.264/AAC in the system `libavcodec` *alongside* the
base `ffmpeg-free` (additive — no `dnf swap` / `--allowerasing`, no base-package
churn), and the native chromium picks the codecs up. Only the RPM Fusion **free**
release repo is added (removed after install); no nonfree repo needed. The native
browser — 1Password native-messaging and `chrome-*` app_ids — is untouched, which
is what Option B set out to protect. The Options analysis below is kept for history.

> Verified present: `libavcodec-freeworld-8.0.1-6.fc44.x86_64.rpm` in
> rpmfusion-free `releases/44`. The redistribution caveat from Option B still
> applies — this bakes proprietary H.264/AAC into a hosted image, a conscious call.

## Problem

Fedora builds `chromium` with `ffmpeg_branding="Chromium"` / `proprietary_codecs=false`,
so **H.264 and AAC are stripped**. Our image installs that stock package
(`Containerfile`: `dnf5 -y install firefox chromium`), adding nothing codec-related.

Consequences for the native `chromium-browser` (which backs all our web-app launchers):

- **WebRTC H.264 is unavailable** → Teams (and any service that only offers H.264
  video) shows black/no video. This is the concrete breakage we hit.
- **`<video>` H.264/AAC playback fails** → many `.mp4` embeds won't play.
- Open codecs (VP8/VP9/AV1/Opus) already work, so most sites are fine.

Confirm the gap on the host:

```js
// DevTools console on any page:
RTCRtpSender.getCapabilities('video').codecs.map(c => c.mimeType)
// missing "video/H264"  → WebRTC H.264 unavailable
```

## Goal

Native `chromium-browser` gains H.264 (at minimum for WebRTC, ideally for `<video>`
too) **without** giving up the native-browser benefits we deliberately chose:
1Password native-messaging integration and deterministic `chrome-*` app_ids for
niri window-rules / dank-lader matching. Keep the change in the image, not layered.

## Options

### A. openh264 only — freely redistributable (preferred if it suffices)

Cisco's OpenH264 is distributed such that Cisco pays the H.264 royalties, so it is
**freely redistributable** — the cleanest fit for a *published* image
(`ghcr.io/reinier/rheniite`). Fedora ships it via the (often disabled)
`fedora-cisco-openh264` repo.

- Enable `fedora-cisco-openh264` + install `openh264` (and any `chromium`-openh264
  glue package Fedora provides).
- **Targets WebRTC H.264** — i.e. exactly the Teams case. Does *not* add `<video>`
  H.264/AAC playback.
- ⚠️ **Must validate:** it is not confirmed that Fedora's stock `chromium` consumes
  the *system* openh264 for WebRTC (openh264 wiring on Fedora has historically been
  Firefox-centric). If stock chromium ignores it, this path is a dead end and we
  fall through to Option B. **Validate before committing.**

### B. `chromium-freeworld` (RPM Fusion) — complete, but proprietary

Same Chromium built with `ffmpeg_branding="Chrome"` + `proprietary_codecs=true`;
bundles openh264 for WebRTC and adds HEVC/AAC.

- Enable RPM Fusion free + nonfree, replace `chromium` → `chromium-freeworld`.
- ✅ Fixes **both** WebRTC and `<video>` playback; stays a native browser.
- ⚠️ **Redistribution caveat:** this bakes **proprietary H.264/AAC** into a publicly
  hosted image — precisely the patent situation Fedora avoids. For a *personal*
  image it is a pragmatic call, but it must be a conscious one.
- ⚠️ Third-party repo (larger trust surface); `chromium-freeworld` can lag Fedora's
  `chromium` on version/security bumps.

### C. Do nothing — keep the `teams_for_linux` Flatpak (status quo)

Teams works via its bundled Electron codecs; native Chromium stays codec-limited.
Zero image change. Acceptable if Teams is the only real pain point.

## Recommendation

1. **Validate Option A first** on the host (layer `openh264` + repo via
   `rpm-ostree install`, re-run the `getCapabilities` check). Cheapest and cleanest
   legally.
2. If A doesn't light up `video/H264` in stock chromium, decide consciously between
   **B** (complete codecs, accept proprietary-in-published-image) and **C** (stay on
   the Flatpak workaround). If the image ever goes public-facing beyond personal use,
   prefer C or make the image private before choosing B.

## Implementation sketch (Option B, if chosen)

In `Containerfile`, near the browser stage:

```dockerfile
# RPM Fusion (free + nonfree) for full-codec chromium-freeworld.
RUN dnf5 -y install \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
 && dnf5 clean all

# Full-codec Chromium (H.264/HEVC/AAC) in place of Fedora's stripped chromium.
RUN dnf5 -y install firefox chromium-freeworld \
 && dnf5 clean all
```

Then remove the plain `chromium` install and reconcile `firefox` (leave as-is, or
consider `firefox` + `mozilla-openh264` separately).

## Verification (after rebuild + reboot)

- `RTCRtpSender.getCapabilities('video')` now lists `video/H264`.
- A Teams test call shows local + remote video.
- An H.264 `.mp4` plays in a plain `<video>` tag.
- 1Password extension still connects (native messaging intact).
- Web-app app_ids unchanged (`niri msg windows` still shows `chrome-*-Default`),
  so dank-lader / window-rules still match.

## Follow-up once native codecs work

- Drop the `teams_for_linux` Flatpak + its Wayland override from
  dotfiles-rheniite `run_onchange_install-flatpaks.sh`.
- Restore the `MSTeams.desktop.tmpl` web-app launcher and re-point the dank-lader
  **Microsoft Teams** entry back to `gtk-launch MSTeams` (was removed in the
  flatpak switch, commit `c91c83f`).

## References

- niri#1983 — no `InteractiveScreenshot` portal (unrelated, but the reason Gradia
  needs its capture workaround; noted here only to avoid confusion).
- Fedora Chromium codec policy: `ffmpeg_branding="Chromium"` strips H.264/AAC.
- RPM Fusion `chromium-freeworld`; Fedora `fedora-cisco-openh264` repo.
