# CurseForge kit (prepared, NOT submitted)

Everything needed for one official StackRivals project serving every WoW client. **Nothing is
created, uploaded or published without your GO.** The process and the GO lists are in
`docs/RELEASE_PLAN.md`.

## What CurseForge does (checked 4 Nov 2026)

Sources:
* support.curseforge.com: Multi-TOC, Upload API, Creating a project, Moderation Policies, Project
  statuses
* CurseForge app release notes 1.321 / 1.324
* live project file pages
* the BigWigsMods packager

| Question | Answer |
|---|---|
| One project for several WoW versions? | **Yes.** One file can be tagged with several flavors. Live examples: VersionCheck is tagged Retail + Forever + MoP Classic + Titan Reforged Classic + Classic; AllTheThings is tagged with six flavors |
| Does CurseForge read our TOC to tag flavors? | **No evidence it does.** The author tags game versions on upload (or the BigWigs packager does it from the TOC before uploading). Tags can be edited later |
| Does our universal ZIP (one TOC, `## Interface: 16001, 11509, 120105, 20506, 50504, 38002`) work? | **Yes**, as long as the upload is tagged correctly. Every target client reads comma interface lists. CurseForge's only TOC check is that the TOC name starts with the folder name (ours: `StackRivals/StackRivals.toc`). **No suffixed TOCs are needed**, so the engine and the file list exist once |
| Flavor names on CurseForge | Retail · Classic (1.15.x; no separate Hardcore / SoD flavor) · Classic TBC (Anniversary, 2.5.x) · MoP Classic · Titan Reforged Classic · **Forever** (1.60.1; the app detects Forever installs since 1.324, 18 Oct 2026) |
| Not yet confirmed | whether 12.1.5, 1.15.9 and 3.80.2 are selectable yet (the version list needs a login token). `tools/curseforge_upload.py` then picks the nearest lower version and says so |
| Alpha / Beta / Release | Release syncs to the app by default; Beta and Alpha only reach users who opted in (all are listed on the website). **A project needs one Release file before it syncs to the app.** "Release Options" can hold a file after review until you release it by hand |
| Moderation | Starts with the first file. Review time isn't published. A **rejected project can't be re-evaluated**, so get the description right the first time |
| Rules that touch us | English, grammatical description. Logo 400×400 PNG, not blank, no copyrighted art. A changelog on every file. `.zip` only, under 2 GB. **No external download links.** Community and donation links only at the bottom, modest size (we have no donation link). AI-made showcase images need a visible label; our screenshots will be real |
| Blizzard AddOn policy | free (no premium versions, paywalls, ads or in-game donation requests); code readable, not obfuscated; no harm to realms or players. **StackRivals meets all of these**: readable Lua, no libraries, free, no ads |

## Pipeline (manual, on purpose)

1. `tools/build_release.sh` validates the addon, runs the tests and builds `dist/StackRivals-<v>.zip`.
   It checks the ZIP against the commit and writes a manifest with the SHA-256 and the clients.
2. `python3 tools/curseforge_upload.py --zip dist/StackRivals-<v>.zip --type beta --clients forever,vanilla`
   is a **dry run**. It re-checks the ZIP against the commit, reads the changelog entry and prints
   the exact metadata and flavor tags. Only the clients you name get tagged.
3. Upload, by hand on authors.curseforge.com (recommended for the first file) or with the same
   script. The script uploads only with `--go "I approve uploading StackRivals <v> as <type>"`,
   `--project <id>` and `CF_API_TOKEN` set. It always sets **release manually**
   (`isMarkedForManualRelease`).
4. After CurseForge's review: you press release on the website.

**There is no CI upload.** No token is stored in GitHub, and there is no tag-push workflow. The
BigWigs packager would upload every untagged build as Alpha and can't hold a file for manual
release.

## Project fields

| Field | Value |
|---|---|
| Name | StackRivals |
| Summary (≤ 120 chars) | A falling-block puzzle game inside WoW: Loot Duels for up to 40, duels, spells and daily challenges. |
| Main category | Minigames |
| Extra categories | Miscellaneous |
| License | Custom: paste `LICENSE` (All Rights Reserved; readable source as Blizzard's policy requires) |
| Logo | `docs/assets/curseforge-logo.png` (400×400 PNG, the red X mark) |
| Source / issues | https://github.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon (public) |
| Game versions on the first file | **only the clients that passed the Beta GO list** (plan: Forever + Classic) |

## Description (English, paste as is; keep the status box in step with the tests)

> **Status of this version.** StackRivals 0.8.x is a **Beta**.
> Tested in the real game client: [FILL IN: e.g. "WoW Forever and Classic Era: solo modes"].
> Multiplayer features are [FILL IN: "verified on …" / "not verified with real players yet"].
> Other WoW versions are included and pass our automated tests, but haven't been tested in their
> real client yet. If you play one of them, `/sr report` and a comment help us a lot.

**StackRivals** is a fast falling-block puzzle game you play inside World of Warcraft: in the
queue, between pulls, or to settle who gets the loot. It gets out of your way the moment combat
starts. Same pieces, rotation and scoring as **stackrivals.io**.

**⚔ LOOT DUEL: compete for dungeon and raid loot with up to 40 players!**
Instead of `/roll`, the group races for an item: everyone plays the **same pieces at the same
time** for one minute, and the highest replay-checked score wins.
- Invite your party, the whole raid or selected players. Nobody is entered automatically; everyone
  clicks Join or Pass.
- A live leaderboard during the race; CONGRATULATIONS for the winner on every player's screen; TIE
  when it's a tie (then roll off).
- Fair by design: the pieces come from every player's secret share, so nobody (not even the
  leader) can pick them. The best runs are replayed on every PC.
- **It never hands out items.** The loot master (or the item's holder) does that by hand, under
  your group's normal loot rules. Agree on it before the pull.

**QUICKPLAY: challenge other StackRivals players.** Quick Duel and Spell Duel with players WoW
lets the addon reach: your guild, group, friends, Battle.net friends and recent rivals. There is
no global matchmaking server: addons can't go online.

**SPELL BATTLE: use spells and strategy.** Pick four spells, build mana by clearing lines, and
bomb, freeze or black out your rival. Play it against the bot (five levels, Rookie to Rival) or in a duel.

**Also included**
- **Classic** (endless), **Time Trial 2:00**, **Daily Challenge** (same pieces for everyone that day)
- **Guild Duels**: challenge guild members, friends, your group or anyone by name
- **Match chat** during duels (text within one faction, quick messages across factions)
- **Profile and Sync**: link your stackrivals.io account and move challenge codes in and out
  (copy and paste: the addon never connects to the internet)
- Pauses itself in combat and hands every key back to WoW; never acts in combat
- Keeps an unfinished run through `/reload` and logout
- Rebindable keys, scalable window, minimap button, "How to play"
- **Free. No ads, no paid features, no account needed.**

**Supported WoW versions**
| Version | Status |
|---|---|
| WoW Forever | [FILL IN after the client test] |
| Classic Era (incl. Hardcore and Season of Discovery realms) | [FILL IN] |
| Retail (Midnight) | included; automated tests only so far |
| Burning Crusade Classic Anniversary | included; automated tests only so far |
| Mists of Pandaria Classic | included; automated tests only so far |

**Known limitations**
- Multiplayer uses WoW's addon messages, so it reaches only the players WoW lets addons talk to.
  Duels across realms need connected realms or a Battle.net friendship in the same WoW version.
- **Retail and WoW Forever block addon messages during boss fights, Mythic+ runs and PvP
  matches.** Duels and Loot Duels wait until the fight is over. A Loot Duel can't be started
  during one.
- WoW Forever: whether Loot Duel works inside dungeons between pulls is [FILL IN after test F2].
- Trial and Veteran accounts can't send addon messages, so they can't use the multiplayer modes.
- Results are checked by the other players' addons (peer-checked), not by a server. That's good
  against mistakes and naive cheats, but not proof against a modified addon. Use Loot Duel with
  people you trust, like any loot rule.

**Commands**
`/sr` open · `/sr loot` Loot Duel · `/sr quickplay` · `/sr spell` · `/sr daily` · `/sr settings` ·
`/sr report` (copy a diagnostics line for bug reports) · `/sr commtest` (check addon messages in
your group) · `/sr version`

**FAQ**
- *Does it hand out loot?* No. It only decides a winner; your loot master hands out the item.
- *Is there online matchmaking or a ranked ladder in WoW?* No. WoW addons can't go online. You
  play people WoW connects you with: guild, group, friends.
- *Does it cost anything?* No. It's free, with no ads and no paid features.
- *Will it get me killed?* It pauses the moment combat starts and gives your keys back.
- *Something's wrong?* Type `/sr report`, copy the line, and post it with a short description
  below or on GitHub. The line has no character or chat data.

**Bug reports and support**
Comments here, or https://github.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/issues: please
include the `/sr report` line.

Not affiliated with or endorsed by Blizzard Entertainment.

*Community:* StackRivals Discord: discord.gg/KV5dTAn8c · Website: stackrivals.io

## Screenshots (real WoW only, taken during the client tests; never the developer previews)

The developer previews in `docs/preview/` are simulated (a WoW API mock) and are **not** used on
CurseForge.

| # | Shot | Client | Taken |
|---|---|---|---|
| 1 | Loot Duel result in a dungeon party: CONGRATULATIONS, WINNER / LOST / PASSED | Forever (F1/F2) | no |
| 2 | Loot Duel live leaderboard beside the board during a race | Forever or Classic Era | no |
| 3 | Mode menu with the LOOT DUEL card and filled records | any | no |
| 4 | Spell Battle vs Bot mid-match (spells and mana visible) | any | no |
| 5 | Quickplay / duel lobby with two character cards | Classic Era or Forever | no |
| 6 | The pause screen right after combat started | any | no |

1920×1080, default UI scale. Crop or blur other players' names, chat and guild names, unless they
agree.

## Per-upload checklist

- [ ] `docs/RELEASE_PLAN.md` §3 (Beta) or §4 (Release) GO list done for **each** client tagged
- [ ] `tools/build_release.sh` green; ZIP sha256 noted; CI run linked
- [ ] `tools/curseforge_upload.py … --clients <only the ones that passed>`: dry run reviewed
- [ ] Status box and "Supported WoW versions" table match the test logs
- [ ] Changelog = the version's CHANGELOG entry (the script fills it in)
- [ ] Release type set; **release manually** after review
- [ ] Your written GO
