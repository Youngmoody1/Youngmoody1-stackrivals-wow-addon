# Forever launch runbook

WoW Forever opens **4 Nov 2026 15:00 PST = 5 Nov 2026 00:00 Copenhagen**. The beta closed on
23 Oct, so the first Forever test happens on launch night. **No build is called "Forever tested"
until that test passes.**

## Release candidate

- `dist/StackRivals-<version>.zip` from `tools/build_release.sh` (reproducible; its `.sha256` and
  `.json` record the version, commit and checksum).
- The same ZIP serves every client; the TOC already lists Forever's beta interface number 16001.
- Keep every previous ZIP (`dist/` and the backup folder on the owner's PC) for rollback.

## Before launch

- [ ] Real Retail/Classic pass (docs/TEST_DAY.md) → fixes → new 0.3.x build
- [ ] CurseForge page created; Beta uploaded (owner approval) — see docs/CURSEFORGE.md
- [ ] Forever client downloaded in Battle.net as soon as it's offered
- [ ] Copy the latest ZIP into the Forever game folder's `Interface\AddOns` (Battle.net → WoW
      Forever → gear → *Show in Explorer*), or link this chat to that folder and let Claude install it

## Launch night (00:00–01:00)

1. **Interface check:** in game, `/sr version` (or `/dump select(4, GetBuildInfo())`).
   - 16001 → nothing to change.
   - Other number → add it at the front of `## Interface:`, bump the patch version, rebuild
     (5 minutes). Until then players can use *Load out of date AddOns*.
2. **10-minute test** (docs/TEST_DAY.md section 1) in Forever, with `/console scriptErrors 1`.
3. **Collect:** "færdig" → Claude reads StackRivals' saved data (the `diag` block shows the exact
   Forever build and interface) and the screenshots.
4. **Decide:**
   - Clean → owner approves → upload as **Release**, game version Forever.
   - Small problem → hotfix (below), retest the failing step, then release.
   - Serious problem (Lua error on load, blocked actions, keys stuck) → don't release; keep the
     Beta; fix tomorrow.

## Hotfix procedure (target: under 1 hour)

1. Reproduce in the mock if possible (add a test), fix, `lua5.1 tests/run.lua`.
2. Bump the patch version in the TOC + CHANGELOG entry.
3. `tools/build_release.sh` → new ZIP + checksum.
4. Install locally (Claude via the linked folder), owner restarts the client and retests the step.
5. Owner approves → upload.

## Rollback

- **Player side:** StackRivals can be disabled in the AddOns list; nothing else depends on it.
  Saved records survive across versions (validated on every load; unknown fields are ignored).
- **CurseForge:** files can't be "reverted". Re-upload the previous good ZIP with a higher patch
  version (e.g. 0.3.2 = contents of 0.3.0) and archive the bad file.
- **Owner's PC:** previous builds are in `World of Warcraft\StackRivals-backups\`.

## Fallbacks

- **CurseForge not approved by launch:** share the ZIP via a GitHub Release (owner approval) with
  the manual install steps from README, and upload to CurseForge as soon as it's approved.
- **Forever changed an API we use:** only the UI layer can be affected (docs/COMPATIBILITY.md).
  Guard the call with feature detection, rebuild, and retest.
