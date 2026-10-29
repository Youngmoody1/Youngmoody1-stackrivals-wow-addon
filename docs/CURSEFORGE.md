# CurseForge listing (draft — not submitted)

## Process (checked 29 Oct 2026, CurseForge support docs)

- A project can be created and its page filled in **without** a file. It is only submitted to
  moderators when the **first file** is uploaded; that file shows "Under Review" until approved.
  No review time is published.
- Title/description must be English; license chosen from the list (or custom); a logo is required
  (`docs/assets/curseforge-logo.png`, 400×400). Up to 4 extra categories; unrelated ones get sent back.
- Upload a real `.zip`. Release types: Release / Beta / Alpha — only *Release* files sync to the
  CurseForge app by default.
- To avoid waiting for review on launch night: create the page now and (with owner approval) upload
  0.2.0 as a **Beta** file for *Forever* before 4 Nov, so the project itself is approved in advance;
  then upload the launch-tested build as **Release**.

**Project name:** StackRivals
**Game / flavor:** World of Warcraft — flavor "Forever", game version 1.60.1 (interface 16001), as
other Forever addons list it today. Re-check the game version on launch day before uploading.
**Category:** Minigames (secondary: Miscellaneous)
**License:** All Rights Reserved (source visible in the download, as Blizzard's policy requires)
**Summary (short description, ≤ 120 chars):**
Competitive falling-block puzzle minigame for WoW Forever. Blitz 2:00, Daily seed, combat auto-pause.

---

## Description

**StackRivals** brings a fast, competitive falling-block puzzle game into World of Warcraft: Forever.
Play a quick round while you wait for the dungeon queue, the group or the boat — and the game gets
out of your way the second combat starts.

It's the same game as **stackrivals.io**: same pieces, same rotation and wall kicks, same scoring.

### Modes
- **Blitz 2:00** – the highest score in two minutes. Perfect for short breaks.
- **Daily Blitz** – every player gets the *same pieces* on the same day. Compare scores with your guild.
- **Classic** – endless; the speed goes up every 10 lines.

### Built for WoW
- **Combat auto-pause** – the run pauses, your keys go straight back to WoW and the window hides
  until the fight is over.
- **Never steals your keys** – the keyboard is only used while a run is live. Paused or on the menu,
  WoW gets every key. Enter pauses and opens chat.
- **Never lose a run** – `/reload` or logout keeps your unfinished game.
- **Personal records** per mode, Daily best and lifetime stats, plus one-click *Share to guild / group*.
- Hold, 5-piece preview, ghost piece, combos and back-to-back bonuses.
- Rebindable keys, scalable window, sound toggle, minimap button.
- Lightweight: no libraries, nothing runs while the window is closed.

### Commands
`/sr` (or `/stackrivals`) to open · `/sr blitz` · `/sr daily` · `/sr settings` · `/sr minimap`

### Supported clients
- **WoW Forever** — supported.
- Retail, Classic Era / Hardcore, Anniversary and Classic progression — *planned*; they will be added
  here as each one passes a real in-game test.

### Install
CurseForge app: search "StackRivals" and install. Manual: unzip into
`World of Warcraft\<your game folder>\Interface\AddOns\` so that `AddOns\StackRivals\StackRivals.toc`
exists, then restart the game.

### Default controls
←/→ move · ↑/Z rotate · ↓ soft drop · Space hard drop · C hold · P pause (all rebindable)

Records are stored on your computer and are not verified online.

Free, no ads, no donations, no online accounts. Feedback and bug reports welcome in the comments.

### Beta status (shown at the top of the description while the file is a Beta)
> **Beta.** StackRivals has been tested automatically and in [Retail/Classic Era — fill in after the
> real test]. It has **not yet run in the live WoW Forever client**, which opens on 4 November.
> Please report anything odd in the comments.

### Bug reports
Comments here, or GitHub issues: https://github.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/issues
— include `/sr version` and any error text.

### Version history
- 0.2.1 – compatibility fixes for modern clients.
- 0.2.0 – How to play, Records (top 5), pause-key resume, fit-to-screen, review fixes.
- 0.1.0 – first playable build.

---

**Keywords / tags:** StackRivals, WoW Forever, block puzzle, falling blocks, minigame, puzzle game,
highscore, daily challenge, queue game

## Screenshots to take (in WoW Forever, 1920×1080, UI scale default)

1. Window over a capital city, mid-game with a clear callout ("DOUBLE"/"QUAD") on screen.
2. Mode menu with records filled in (Blitz best + Daily "Today").
3. Blitz "TIME!" screen with **NEW BEST**.
4. Pause screen after entering combat ("You entered combat…"), character visibly in combat.
5. Settings with the key-binding panel.
6. Minimap button tooltip.
