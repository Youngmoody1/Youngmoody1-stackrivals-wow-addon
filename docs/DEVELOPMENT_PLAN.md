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
| 4 | Red box in Spell Battle (user, real Classic Era client) | Two causes found and fixed with regression tests: (a) the 5th NEXT piece drawn over the bot's mini board after any phase change (most likely: an I piece is red); (b) the Bomb target outline above the board. In the 0.7.2 test ZIP. **Needs a screenshot / re-test to confirm** |

## 3. Real client tests (Classic Era first)

| Step | Status |
|---|---|
| 0.3.1 smoke test | VERIFIED (user) |
| 0.7.0 installed in Classic Era | VERIFIED (files); features NOT TESTED |
| 0.7.0 test points 1–8 (`TEST_LOG_CLASSIC_ERA.md`) | waiting for the user |
| 0.7.2 test ZIP install | only after the 0.7.0 report and approval |

## 4. Universal compatibility: all official WoW clients (0.8.0, `feature/multi-client`)

| Requirement | Status |
|---|---|
| Clients researched (project ID, interface, TOC suffix, API family, restrictions) | DONE: `docs/COMPATIBILITY.md`, `tools/clients.json` (sources: warcraft.wiki.gg, Blizzard posts) |
| Installed clients on your PC checked (read only) | DONE: Classic Era 1.15.9.70576, Forever 1.60.1.70755; Retail and Anniversary present but outdated; Mists folder without the game |
| One code base: client layer (`Core/Client.lua`), feature detection, Forever as its own Mainline-family client | DONE (mock-tested) |
| WoW's addon chat lockdown (Retail / Forever): messages held, Loot Duel refuses to start and says why, timers wait mid-race | DONE (mock + simulated multiplayer) |
| Trial / Veteran accounts | DONE (said plainly) |
| TOC: exactly the live clients; one universal ZIP (per-client ZIPs would be identical) | DONE; validator checks it |
| Mock test matrix: 9 client profiles + Loot Duel on 5 client types | DONE (`tests/test_clients.lua`) |
| **Forever in the real client**: interface number, addon messages inside dungeons, loot methods | NEXT: `docs/FOREVER.md` S1–S7, F1–F9 (needs your approval to install) |
| Retail, Anniversary, Mists in the real clients | LATER: update the clients in the launcher first; 10-minute test each |
| Cross-client Battle.net (Retail ↔ Forever) | unknown: F8 |

## 5. Out of scope here

* The website and Shards: separate projects.
* A live web connection from WoW (addons have no internet). The Quickplay web adapter stays
  "not connected".
* Gold, bets, and automatic loot.
