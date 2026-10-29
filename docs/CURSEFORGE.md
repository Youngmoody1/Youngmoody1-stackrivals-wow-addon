# CurseForge submission kit (prepared — NOT submitted)

Everything needed to create the project and upload the first file. Nothing is uploaded or
published without the owner's explicit approval.

## What we verified (CurseForge support docs, 29 Oct 2026)

- **Moderation starts at the first file.** A project page can be created and filled in without a
  file; uploading the first file submits it for review ("Under Review"). No review time is published.
- **Release options:** the upload form has a "Release Options" setting to publish the file
  automatically after moderation *or at a later date*. We have not seen the form ourselves, so
  confirm the exact choices when uploading.
- **Release types:** *Release* syncs to the CurseForge app by default and is what the main download
  button gives. *Beta* and *Alpha* reach app users only if they opted in to those channels; they are
  still listed on the website. A project needs an approved Release (or Beta) to be available in the
  app; with only Alpha files it is website-only. **So a Beta is public on the website.**
- **Multi-TOC / flavours:** one project can serve several WoW versions. Each TOC file must start
  with the folder name, and each needs an interface number. **Game versions are tagged by hand on
  upload** and can be edited later. We use one TOC with a comma-separated `## Interface:` list —
  the same approach Deadly Boss Mods uses in its current Forever-ready release
  (`## Interface: 11509, 16001, 20506, …`, checked in the copy on the owner's PC).
- **Project requirements:** unique name; English title and description; a sufficient, correct
  description; a logo; license from the list or custom; main category + up to 4 related ones
  (unrelated categories get sent back); a real `.zip` under 2 GB.

## Recommended path to beat launch-night moderation

1. Owner creates the project page now (text below, logo `docs/assets/curseforge-logo.png`).
2. After the first real-client test (Retail/Classic) passes: upload `StackRivals-0.3.x.zip` as
   **Beta**, game version **Forever** (+ only the clients that passed a real test), with the Beta
   notice at the top of the description, and — if the form offers it — *publish at a later date*.
3. Launch night: real Forever test → upload the verified build as **Release**.

## Project fields

| Field | Value |
|---|---|
| Name | StackRivals |
| Summary (≤ 120 chars) | Fast falling-block puzzle minigame for WoW Forever. Blitz 2:00, Daily challenge, auto-pause in combat. |
| Main category | Minigames |
| Extra categories | Miscellaneous |
| License | Custom: "All Rights Reserved" — paste `LICENSE` from the repo |
| Logo | `docs/assets/curseforge-logo.png` (400×400) |
| Source / issues | https://github.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon (public) |
| Game versions on first upload | Forever only (add others only after their real test) |

## Description (paste as is; delete the Beta box once Forever is verified)

> **Beta.** StackRivals has passed automated tests and a real test in [CLIENT — fill in].
> It has **not yet run in the live WoW Forever client**, which opens on 4 November. Please report
> anything odd in the comments.

**StackRivals** is a fast falling-block puzzle game you can play inside World of Warcraft: Forever,
in the queue, while waiting for your group, or between quests. It gets out of your way the
moment combat starts.

It is the same game as **stackrivals.io**: same pieces, same rotation and wall kicks, same scoring.

**Modes**
- **Blitz 2:00**: the best score you can make in two minutes.
- **Daily Blitz**: every player gets the *same pieces* on the same day (resets 00:00 UTC). Compare scores with your guild.
- **Classic**: endless; the speed goes up every 10 lines.

**Made for playing inside WoW**
- **Pauses itself in combat.** The game stops, every key goes back to WoW, and the window hides until the fight is over.
- **Never takes your keys.** Keys are only used while a run is live. Paused or on the menu, WoW gets every key. Enter pauses and opens chat.
- **Never lose a run.** `/reload` or logging out keeps your unfinished game.
- **Personal records**: top 5 per mode, today's Daily score, lifetime stats, one-click *Share to guild / group*.
- Hold, 5-piece preview, ghost piece, combos and back-to-back bonuses.
- Rebindable keys, scalable window, sound toggle, minimap button, "How to play" for new players.
- Lightweight. No libraries, and nothing runs while the window is closed.

**Commands**
`/sr` (or `/stackrivals`) open · `/sr blitz` · `/sr daily` · `/sr classic` · `/sr settings` · `/sr minimap` · `/sr reset`

**Default controls** (all rebindable)
←/→ move · ↑ / Z rotate · ↓ soft drop · Space hard drop · C hold · P pause/resume

**Install**
CurseForge app: search "StackRivals". Manual: in Battle.net select WoW Forever → gear icon →
*Show in Explorer*, open `Interface\AddOns` and unzip there so that
`AddOns\StackRivals\StackRivals.toc` exists, then fully restart the game.

**FAQ**
- *Does it work in Retail / Classic Era / Anniversary?* Planned. Each is added here only after it
  passes a real in-game test.
- *Are scores online / ranked?* No. Records are stored on your computer and are not verified. The
  Daily challenge is fair because everyone gets the same pieces, but there is no online leaderboard yet.
- *Will it get me in trouble in combat?* No. It never acts in combat; it pauses and hands back your keys.
- *Does it cost anything?* No. Free, no ads, no donations, no accounts.
- *My keys feel wrong.* Settings → click a key → press the new one. "Default controls" resets them.
- *Something broke.* Post a comment or open a GitHub issue with `/sr version` and the error text.

**Bug reports**
Comments here, or https://github.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/issues.
Include `/sr version` and any error text.

Not affiliated with or endorsed by Blizzard Entertainment.

**Version history**: see Changelog (paste the top entries of CHANGELOG.md into each file's changelog field).

---

## Keywords

StackRivals, WoW Forever, Classic Plus, falling blocks, block puzzle, puzzle game, minigame, mini game,
queue game, daily challenge, highscore, arcade.
(Never use a third-party game's trademark as a keyword.)

## Screenshots (real, in-game, after the client test — never the developer previews)

1. Window over a busy city, mid-game, a "DOUBLE"/"QUAD" callout visible.
2. Mode menu with records filled in.
3. Blitz "TIME!" with NEW BEST.
4. The pause screen right after combat ("You entered combat…") with the character in combat gear.
5. Settings with key bindings.
6. Records screen.

1920×1080, default UI scale, no personal chat or names visible (crop or blur).

## Per-upload checklist

- [ ] `tools/build_release.sh` passes; use the ZIP from `dist/` and note its sha256
- [ ] Release type: Beta (pre-launch) / Release (verified on Forever)
- [ ] Game versions: only clients with a real passing test
- [ ] Changelog field: the version's CHANGELOG entry
- [ ] Beta box in the description matches the real test status
- [ ] Owner approved this upload
