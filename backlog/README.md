# backlog

Planned but not-yet-done work on the **Rheniite image** — one Markdown item per
idea. These are image-level concerns (the `Containerfile`, baked packages, repos,
signing, first-boot defaults); dotfiles/config work lives in the separate
`dotfiles-rheniite` repo, not here.

Think of it as a lightweight TODO with room to reason: capture the problem, the
options and their trade-offs, and a recommendation, so a change can be picked up
later (by you or by Claude) without re-deriving the analysis.

## Conventions

- **One item per file**, `kebab-case.md` named after the change
  (e.g. `chromium-free-codecs.md`).
- Start each item with a short frontmatter-style block:
  - `Status:` proposed | accepted | in-progress | done | dropped
  - `Created:` `YYYY-MM-DD` (absolute dates — no "last week")
  - `Area:` what it touches (e.g. `image (Containerfile)`)
  - `Related:` links to commits, other repos, upstream issues
- Then the body: **Problem → Options (with trade-offs) → Recommendation →
  Implementation sketch → Verification**. Include the concrete commands/diffs so
  the item is actionable, not just aspirational.
- When an item ships, either set `Status: done` (with the implementing commit) or
  delete the file — don't leave stale plans lying around.

## Items

- [chromium-free-codecs.md](chromium-free-codecs.md) — native Chromium with H.264
  (WebRTC/`<video>`) so the `teams_for_linux` Flatpak workaround can be retired.
- [synology-drive.md](synology-drive.md) — native Synology Drive client (COPR RPM,
  `-noextra` variant) with the `/opt` payload relocated into `/usr` for bootc.
