# Pin rheniite to stable Zirconium releases (instead of rolling `:latest`)

- **Status:** proposed
- **Created:** 2026-07-14
- **Area:** image (`Containerfile`) + CI (`.github/workflows/build.yaml`)
- **Related:** `Containerfile` `FROM ghcr.io/zirconium-dev/zirconium:latest`; the
  "personal fork fallback" note in `README.md` / `Containerfile` (the manual
  band-aid this item replaces with a real mechanism).

> **What "stable releases" means here.** Zirconium does **not** publish a
> separate `stable`/`gts` channel, and it cuts **no GitHub Releases or git tags**
> (`repos/zirconium-dev/zirconium` has none). Its `:latest` *is* the current
> Fedora-release stream — but it is **rolling**, rebuilt continuously. The only
> "releases" it offers are the **immutable, cosign-signed dated snapshots** it
> pushes alongside `:latest`. So "move off git/rolling → stable releases" concretely
> means: **pin to a specific signed snapshot and promote it deliberately**, instead
> of auto-inheriting every upstream build within a day.

## Problem

`FROM …/zirconium:latest` + a **daily rebuild cron** (`build.yaml`: `cron: "0 2 * * *"`,
`podman build --pull=always`) means every upstream Zirconium change reaches the
booted machine within ~24h, **unreviewed and untested by us**. The README already
admits the failure mode ("if an upstream update ever regresses…") and its only
remedy is manual: hand-edit `FROM` to the personal `ghcr.io/reinier/zirconium`
fork. That's reactive, undocumented-when, and loses reproducibility — there is no
record of *which* base a given rheniite build used, and no clean rollback target.

## What Zirconium actually publishes (researched 2026-07-14)

Registry `ghcr.io/zirconium-dev/zirconium` tag scheme (from the GHCR v2 API):

- **`latest`** — rolling, current Fedora **release** stream. Multiarch OCI index.
  Current digest: `sha256:96c412220c1db9171697ebb56865c84e127f52dcc5464b59eefda0a3dd74c41c`.
- **`latest.YYYYMMDD`** and **`YYYYMMDD`** — **immutable dated snapshots** of that
  stream (one per build). These are the de-facto "stable releases."
- **`rawhide` / `rawhide.YYYYMMDD`** — Fedora **dev** stream (do not use).
- **`latest-amd64` / `latest-arm64`** — per-arch manifests.
- **No `stable` / `gts` tag. No GitHub Releases. No git version tags.**
- **Signed:** repo ships `cosign.pub`; the registry carries `…​.sig` sigstore
  attachments for each build (same mechanism rheniite already uses downstream).

Built with **mkosi** (not a Containerfile), default branch `main`, community on
Discord — i.e. there is no upstream "release process" to hook into beyond the tags
above. Pinning is therefore *our* responsibility.

## Options

### A. Pin the base to an immutable snapshot, bump via Renovate (recommended)

Pin `FROM` to a specific dated snapshot **by digest**, and let
[Renovate](https://docs.renovatebot.com/) open a PR when a newer snapshot exists.
CI (build + `bootc container lint`) runs on that PR, so a regressing base is caught
**before** merge instead of on the running laptop.

- ✅ Reproducible: a given rheniite commit always builds on the exact same base.
- ✅ Regressions gated by PR CI; merging is a deliberate act.
- ✅ Rollback = `git revert` the pin bump (a known-good base by construction — what
  the fork-fallback note was doing by hand).
- ✅ Cadence is a knob (Renovate `schedule:` weekly → weekly "stable" promotions).
- ⚠️ Security/base fixes land only when you merge the bump → mitigate with a tight
  schedule and/or `automerge` on green CI.

### B. Digest-only pin of `:latest` (variant of A)

`FROM …:latest@sha256:…`, Renovate `pinDigests` tracks `:latest`'s digest. Same
gating, but a PR **per upstream push** (≈daily) rather than curated snapshots. Use
if you'd rather review every change; combine with a weekly Renovate `schedule:` to
batch them. (Digest is the real immutability anchor — a tag can be re-pushed, a
digest cannot. Recommendation keeps the digest either way.)

### C. Keep base rolling, but pin what **rheniite** publishes

Leave `FROM …:latest`, but have rheniite emit its own dated tags so the *machine*
can pin/rollback. Doesn't stop a bad base entering a build — weaker on its own, but
a good **complement** to A (see Implementation §3).

### D. Status quo — daily auto-follow + manual fork fallback

Zero work; exactly the risk this item exists to remove. Rejected.

## Recommendation

**A + C, digest-anchored.** Pin the base to a signed dated snapshot *by digest*,
automate promotion with Renovate + CI gating (weekly schedule, optional auto-merge),
**and** have rheniite publish immutable dated tags of itself so `bootc` can pin and
roll back the actual OS. Retire the daily cron (a pinned base rebuilt daily just
re-pushes identical bits). Optionally verify the base's cosign signature in CI
before building, matching the trust rheniite already enforces at runtime.

## Implementation sketch

### 1. Pin the base (`Containerfile`)

```dockerfile
# Pinned to an immutable, cosign-signed Zirconium snapshot. Bumped by Renovate
# (see .github/renovate.json) via a PR that CI builds + lints before merge —
# deliberate, reviewed promotions instead of auto-inheriting every upstream build.
# renovate: datasource=docker depName=ghcr.io/zirconium-dev/zirconium
FROM ghcr.io/zirconium-dev/zirconium:latest.20260713@sha256:96c412220c1db9171697ebb56865c84e127f52dcc5464b59eefda0a3dd74c41c
```

(Replace with the newest `latest.YYYYMMDD` and its digest at implementation time —
`skopeo inspect --format '{{.Digest}}' docker://…:latest.YYYYMMDD`, or the
`docker-content-digest` header from the GHCR v2 manifest endpoint.)

### 2. Automate the bump (`.github/renovate.json`) + enable the Renovate GitHub App

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "schedule": ["before 6am on monday"],
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "matchPackageNames": ["ghcr.io/zirconium-dev/zirconium"],
      "pinDigests": true,
      "versioning": "regex:^latest\\.(?<major>\\d{4})(?<minor>\\d{2})(?<patch>\\d{2})$"
    }
  ]
}
```

The `regex` versioning teaches Renovate to order the `latest.YYYYMMDD` tags so it
picks the newest as an upgrade (default docker versioning won't parse the date).
Add `"automerge": true` to the rule if you'd rather merge-on-green than review each.

### 3. Publish dated + rollback-able tags for rheniite (`build.yaml`)

In the push step, stamp and push an immutable date tag alongside `:latest`, and
sign both:

```bash
DATE_TAG="$(date -u +%Y%m%d)"
for t in latest "${DATE_TAG}"; do
  podman tag "${IMAGE_NAME}:latest" "${REGISTRY}/${IMAGE_NAME}:${t}"
  podman push "${sign_args[@]}" "${REGISTRY}/${IMAGE_NAME}:${t}"
done
```

Then `bootc switch ghcr.io/reinier/rheniite:20260714` pins the machine to a build,
and an old date tag is a re-pin target after several updates (bootc's built-in
rollback only retains the immediately previous deployment). Keeping `:latest` as
the default rebase target is fine; pin per-machine only when you want to hold.

### 4. Retire the daily cron (`build.yaml`)

Remove the `schedule:` block (or drop to weekly as a safety rebuild). With a pinned
base, "pick up new zirconium base images" is now Renovate's job; push-to-`main` +
`workflow_dispatch` remain. Update the README's "How it builds" + the `FROM` comment
in `Containerfile` to describe pin-and-promote instead of daily auto-follow.

### 5. (Optional) Verify the base signature in CI before building

```bash
curl -fsSL https://raw.githubusercontent.com/zirconium-dev/zirconium/main/cosign.pub -o /tmp/zirconium.pub
cosign verify --key /tmp/zirconium.pub \
  ghcr.io/zirconium-dev/zirconium@sha256:96c412220c1db9171697ebb56865c84e127f52dcc5464b59eefda0a3dd74c41c
```

Fails the build if the pinned base isn't a genuine signed Zirconium snapshot —
extends rheniite's existing signed-supply-chain story upstream by one hop.

## Verification

- `podman build` succeeds against the pinned digest; `bootc container lint` passes.
- Open a throwaway Renovate PR (or `renovate --dry-run`) and confirm it proposes the
  next `latest.YYYYMMDD` and that CI runs on it.
- After a push to `main`, confirm both `…/rheniite:latest` and `…/rheniite:YYYYMMDD`
  exist and carry `.sig` attachments (GHCR v2 `tags/list`).
- On a test host: `bootc switch …/rheniite:<date>` pins; `bootc upgrade` is a no-op
  until the pin moves; reverting the base bump in git and rebuilding reproduces the
  prior base (same digest in `podman inspect`).
- Signature policy still holds: an unsigned push is still rejected by `bootc switch`
  (unchanged from today).

## Open question for Reinier

If by "git releases → stable releases" you instead meant **cutting GitHub Releases**
for rheniite (tagged `vX.Y` with changelogs), that's a separate, additive step —
say so and I'll fold a `git tag` + `gh release create` stage into §3. The plan above
reads it as "stop chasing rolling `:latest`, pin & promote signed snapshots," which
is the change that removes the regression risk the README calls out.
