# StackRivals WoW addon: development plan

This plan collects the requirements from the briefs so far. Status words:
**DONE (simulated)** = built, with automatic tests and previews, but not seen in a real client;
**VERIFIED** = observed in a real WoW client; **NEXT** = the next task; **LATER**; **OUT** = not
part of the addon.

Standing rules for every track:
* No merge, release or CurseForge upload without approval.
* No change to the user's installation without a backup and approval.
* No website or Shards work here.
* No automated gameplay or character control.
* No passwords or tokens through the addon.
* Simulations and previews never count as real client tests.

## 1. Loot Duel: up to 40 at once (0.7.2, `feature/loot-duel-raid`)

The text message of 4 Nov mentioned "2–10 in raids". The later 0.7.2 brief and the "40 players"
brief say **2–40 is the priority**. This plan follows 2–40.

| Requirement | Status |
|---|---|
| 2–40 in one race, same pieces, same time (1:00 default), no spells, shared countdown, highest valid score wins; no heats by default | DONE (simulated: 2, 5, 10, 15, 20, 25, 40) |
| Ties, disconnects, unverified results handled (TIE / NO RESULT / NOT CHECKED, never an invented winner) | DONE (simulated) |
| Invite Party / All (confirmed, up to 40) / Selected, All / None, Join / Pass, Ready, nobody auto-entered, no eligibility from class | DONE (simulated) |
| Live list for 40: place, class colour, score, status, scrolling, own row pinned, provisional vs checked, never over the board | DONE (previewed) |
| Efficient protocol: 2 leader messages to start; best 10 (+ ties) replayed instead of 40 × 40; trust limits documented | DONE (simulated), `docs/LOOT_DUEL.md` |
| Seed not steerable by the organizer (commit–reveal, leader committed in the offer) | DONE (tested with a manipulated share among 40) |
| One leaver can't block the others | DONE (lobby, reveal, race) |
| Result colours + icons; class colour on names | DONE (previewed) |
| CONGRATULATIONS / TIE on every participant's PC, only after checks; manual Announce only | DONE (previewed) |
| Loot safety: no loot API, no auto-distribution, no promise of the item | DONE (tested) |
| Keep the menu card and the movable quick button | DONE (0.7.1) |
| Measurements: messages, peak traffic, replays, memory, time to result, consistency | DONE (simulated), `docs/LOOT_DUEL.md` |
| **A real raid of 20–40** | NEXT after approval: `LOOT_DUEL.md` R1–R10 |

## 2. Fixes from real-client observations

| # | Observation | Status |
|---|---|---|
| 3 | "Guild Duel" vs "GUILD DUELS" | DONE on the branch; in the 0.7.2 test ZIP |
| 4 | Red box in Spell Battle (user, real Classic Era client) | Cause found (Bomb target outline above the board). Fixed with a regression test; in the 0.7.2 test ZIP. **Needs a screenshot / re-test to confirm** |

## 3. Real client tests (Classic Era first)

| Step | Status |
|---|---|
| 0.3.1 smoke test | VERIFIED (user) |
| 0.7.0 installed in Classic Era | VERIFIED (files); features NOT TESTED |
| 0.7.0 test points 1–8 (`TEST_LOG_CLASSIC_ERA.md`) | waiting for the user |
| 0.7.2 test ZIP install | only after the 0.7.0 report and approval |

## 4. Universal compatibility: all official WoW clients (NEXT, separate branch)

This is the brief of 4 Nov ("alle de officielle WoW-versioner"). It comes after 0.7.2 and is
built on its code, without starting over.

* **Clients, in priority order:**
  1. Forever and Classic Era / Hardcore;
  2. Retail (Midnight);
  3. Classic Anniversary / TBC;
  4. Mists of Pandaria Classic;
  5. Titan Reforged and other progression versions;
  6. Season of Discovery after client verification.
* PTR / beta clients are researched but kept apart from stable builds. Private servers are not
  supported.
* **One code base:**
  * a compatibility layer for client detection (`WOW_PROJECT_ID`, `GetBuildInfo()`, feature
    checks);
  * client-specific TOC files where useful;
  * the APIs for group, faction / class, Battle.net, addon messages, chat, combat restrictions
    (Retail's newer limits), loot and item links, SavedVariables, and UI templates.
* **Rules:**
  * Forever is its own client type, not Classic Era.
  * A feature a client can't support is shown as unavailable, never as working.
  * Only verified interface numbers are used.
* **Loot Duel per client:** the loot systems differ (Retail: personal loot plus trading).
  Loot Duel only decides; it explains when the item can't be handed over.
* **Multiplayer per client:** PARTY / RAID / GUILD / WHISPER / Battle.net. Cross-client play is
  tested separately.
* **Builds:**
  * decide between one universal ZIP and per-client ZIPs;
  * automated packages with TOCs and checksums.
* **Tests:**
  * a mock test matrix per client type (load, UI, engine, input, spells, Quickplay, group
    detection, Battle.net, account / sync, Loot Duel, SavedVariables, API fallbacks);
  * a real-client test plan per version.
  * Check which clients are installed on the user's PC first, read-only.
* **Deliverables:**
  * the analysis;
  * the compatibility layer;
  * TOC files;
  * CI;
  * packages;
  * the matrix;
  * an install guide per client;
  * a list of limited features;
  * a test plan.

## 5. Out of scope here

* The website and Shards: separate projects.
* A live web connection from WoW (addons have no internet). The Quickplay web adapter stays
  "not connected".
* Gold, bets, and automatic loot.
