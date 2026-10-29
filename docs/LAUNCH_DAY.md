# Forever launch-day plan

WoW Forever goes live **4 Nov 2026, 15:00 PST = 5 Nov 2026, 00:00 Copenhagen**. The beta closed on
23 Oct, so there is no Forever client to test in before that. Character names can be reserved from 27 Oct.

## Before launch (now → 4 Nov)

- [ ] Real-client pass (docs/TESTING_IN_WOW.md) in **Retail** and/or **Classic Era**: the UI, keyboard
      and combat code is the same, so this catches most client issues before Forever exists.
- [ ] Fix whatever that pass finds; re-run `lua5.1 tests/run.lua`; build the ZIP.
- [ ] CurseForge: create the project page (text in docs/CURSEFORGE.md, logo docs/assets/curseforge-logo.png).
      Moderation starts at the **first file upload** — decide whether to upload a *Beta* file early so the
      project is approved before launch (needs owner approval).
- [ ] Download/patch the Forever client in Battle.net as soon as it is offered.

## Launch night (5 Nov, from 00:00 Copenhagen)

1. Install the latest ZIP into the Forever game folder's `Interface\AddOns`, start the client fully.
2. In game: `/dump select(4, GetBuildInfo())` → note the interface number.
   - **16001**: nothing to change.
   - **anything else**: put that number first in `## Interface:` in `StackRivals.toc`, bump the
     version (e.g. 0.2.1), rebuild. Until then players can tick *Load out of date AddOns*.
3. Run docs/TESTING_IN_WOW.md (10 min). Servers will be busy — a quiet corner of the starting zone is
   fine; combat test on any low-level mob.
4. Send back: screenshots, any error text, `WTF\Account\<ACCOUNT>\SavedVariables\StackRivals.lua`.
5. If clean: take the CurseForge screenshots (list in docs/CURSEFORGE.md), owner approves, upload
   the file as **Release** for flavor *Forever*.
6. If not clean: fix → re-test the failing steps → upload.

## Rollback

If a launch-day client change breaks the addon, players can disable it in the AddOns list; nothing
else in the game depends on it. Saved records survive in `StackRivals.lua` across versions
(`schema` field, validated on every load).
