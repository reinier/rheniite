# Stabilize Zirconium's bleeding-edge (git) desktop packages in Rheniite

- **Status:** proposed
- **Created:** 2026-07-14 (findings corrected 2026-07-14 — a stable DMS RPM *does* exist)
- **Area:** image (`Containerfile`) or the `reinier/zirconium` fork
- **Related:** the base's mkosi COPR configs
  (`zirconium-dev/zirconium` → `mkosi.conf.d/fedora/mkosi.conf.d/{avengemedia-danklinux,niri-git}.conf`);
  DMS/niri drive `dank-lader` + niri window-rules. **Must be paired with**
  [own-desktop-config.md](own-desktop-config.md) (the config layer, `zdots`, is
  authored for git-DMS and would skew against pinned-stable binaries).

## Problem

Several **core desktop packages are installed from COPR as git-HEAD snapshots**,
with **no version lock** — every daily Zirconium base build grabs whatever the
COPR's newest build is, so the shell/compositor churn continuously and can regress
between one base and the next. Zirconium's own Renovate only auto-merges container
digest pins; it does **not** pin COPR package versions. This is the churn Reinier
wants to move off of.

## Findings (researched 2026-07-14 — COPR + Fedora + upstream)

Base package sources, with what's *actually* installed **and where the stable
release is packaged**:

| Package | Installed (git) | Source | Stable release | Stable source |
|---|---|---|---|---|
| **niri** | `0.0.git.2812` | `copr:yalter/niri-git` | **`26.04`** | **Fedora 44 main** |
| **dms** / **dms-cli** | `2:0.0.git.4157` | `copr:avengemedia/dms-git` | **`1.5.0`** | **`copr:avengemedia/dms`** (built for fedora-44) |
| **quickshell** | `quickshell-git 0.3.1^830` | `copr:avengemedia/danklinux` | **`quickshell 0.3.0`** | **`copr:avengemedia/danklinux`** (same repo) |
| **dankcalendar** | `dankcalendar-git 0.2.4+git87` | `copr:avengemedia/danklinux` | — *(no tagged RPM)* | git-only; **optional** (not a `dms` dep) |
| dms-greeter | `1.5.0` | `copr:avengemedia/danklinux` | already tagged | — |
| dgop | `1:0.2.3` | `copr:avengemedia/danklinux` | already tagged | — |
| dsearch / danksearch | `0.3.2` | `copr:avengemedia/danklinux` | already tagged | — |
| Terra set, Fedora-main set | released | `terra` / Fedora | released | — |

**A fully stable stack is achievable from existing, maintained repos — no
self-packaging.** Key facts that make it clean:

- The DMS project publishes a **stable sibling COPR `avengemedia/dms`** (`dms 1.5.0`,
  `dms-cli 1.5.0`, fedora-44) alongside the git `avengemedia/dms-git`. Zirconium
  simply lists the `-git` one. (Corroborated by `ngompa/DankMaterialShell 1.4.4`.)
- Stable `dms 1.5.0` declares **`Requires: (quickshell or quickshell-git)`** — the OR
  means the maintainer *explicitly accepts* the stable `quickshell 0.3.0`. So the
  coupling isn't hard: `dms 1.5.0` + `quickshell 0.3.0` is a supported set. (Still
  smoke-test — quickshell is pre-1.0.)
- **`dankcalendar`** is the only holdout (no tagged RPM), and it's **optional** — not
  required by `dms`. Keep the git build, or drop it.

### Two things that shape *where* to do the swap

1. **Epoch trap in a layer.** The git `dms` carries **epoch 2** (`2:0.0.git…`) so it
   outranks stable `0:1.5.0`. Swapping in the Rheniite layer therefore needs an
   explicit downgrade (`--allowerasing`) *and* disabling `avengemedia/dms-git`. A
   **fork** that never enables `dms-git` avoids the fight entirely.
2. **Config coupling.** DMS/niri config (`zdots`) is authored for git-DMS and
   re-applied daily — pinning binaries without owning config just moves the breakage
   to config skew. See [own-desktop-config.md](own-desktop-config.md); do both.

## Options

### A. Swap to the stable sibling repos in the `reinier/zirconium` fork (recommended)

A ~3-line edit to the fork's mkosi config, resolved cleanly at build time:

- `avengemedia-danklinux.conf`: repo `dms-git` → `dms`; package `quickshell-git` →
  `quickshell` (keep `dms dms-cli dms-greeter dgop dsearch`).
- `niri-git.conf`: drop it — use Fedora's `niri`.
- `dankcalendar-git`: keep, or drop.

- ✅ No epoch fight, no layer downgrades; the base you boot is already stable.
- ⚠️ You maintain the fork (already exists/builds) and rebase on upstream; pin the
  `zdots` submodule too (see partner item) so config matches.

### B. Do the swaps in the Rheniite layer (`Containerfile`)

Add `avengemedia/dms`, disable `avengemedia/dms-git`, then `dnf` swap/downgrade:

- niri: `dnf5 distro-sync niri` (Fedora `26.04` — clean, no epoch issue).
- dms: `dnf5 -y --allowerasing downgrade dms dms-cli` to `1.5.0` (epoch-2 trap).
- quickshell: `dnf5 -y swap quickshell-git quickshell`.

- ✅ Keeps riding upstream Zirconium (no fork to maintain).
- ❌ Fights the base each rebuild (epoch downgrades, repo disables) and must be
  re-verified on every base bump.

### C. Freeze the whole base snapshot instead (mitigation)

If you don't want to swap packages at all, pin the base to a tested dated snapshot
([pin-stable-base.md](pin-stable-base.md)) so the git stack stops churning daily.
Not *release* versions, but removes the unreviewed-daily-churn — a valid interim.

## Recommendation

**Option A (fork) + [own-desktop-config.md](own-desktop-config.md)**, as one matched
move: point the fork at the stable sibling COPRs (`avengemedia/dms`, `danklinux`'s
`quickshell`) and Fedora `niri`, pin the `zdots` submodule to a 1.5.0-era commit (or
own the config in dotfiles-rheniite), and smoke-test DMS 1.5.0 on quickshell 0.3.0.

- Keep `dankcalendar-git` (optional) or drop it.
- `dms-greeter` / `dgop` / `dsearch` already track tagged releases — leave them.
- Option B is the fallback if you'd rather not run the fork; Option C if you want the
  smallest possible change now.

## Implementation sketch (Option A — fork mkosi diff)

```ini
# mkosi.conf.d/fedora/mkosi.conf.d/avengemedia-danklinux.conf
[Distribution]
Repositories=copr:copr.fedorainfracloud.org:avengemedia:danklinux
Repositories=copr:copr.fedorainfracloud.org:avengemedia:dms      # was :dms-git

[Content]
Packages=
    dms
    dms-cli
    dms-greeter
    dgop
    dsearch
    quickshell            # was quickshell-git
    # dankcalendar-git    # optional: keep (git) or drop

# mkosi.conf.d/fedora/mkosi.conf.d/niri-git.conf  -> delete the file;
# add `niri` to the Fedora-main package list (zirconium.conf) instead.
```

Verify the stable set resolves for fedora-44 before building:

```bash
# stable dms + its accepted quickshell both exist for fc44:
python3 - <<'PY'
# avengemedia/dms -> dms 1.5.0 ; danklinux -> quickshell 0.3.0 ; Fedora -> niri 26.04
PY
```

## Verification

- Built image: `rpm -q niri dms quickshell` → `26.04`, `1.5.0`, `0.3.0` (no `git`).
- `dms 1.5.0` runs on `quickshell 0.3.0`: DMS launches; dankbar, spotlight, settings,
  lock, notifications all work (the `dms ipc` surface).
- niri `26.04` loads the config; `dank-lader` (Mod+F12) works; window-rules intact.
- `chrome-*` app_id window matching unaffected.
- `bootc container lint` passes; fork builds and boots.

## Decision needed from Reinier

- **Where:** fork (Option A, clean) vs Rheniite layer (Option B, no fork)?
- **dankcalendar:** keep the git build, or drop it (no stable RPM)?
