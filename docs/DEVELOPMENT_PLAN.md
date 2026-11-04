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

## 4b. CurseForge launch (0.8.1 preparation; nothing submitted)

| Requirement | Status |
|---|---|
| One project for every flavor, universal ZIP, correct flavor tags | DONE (prepared): CURSEFORGE.md. Tags are set on upload; only clients that passed their GO list |
| Release pipeline with no auto-publish | DONE: build → dry run (`tools/curseforge_upload.py`) → upload only with GO + token, always "release manually" |
| Alpha / Beta / Release definitions and GO / NO-GO lists | DONE: RELEASE_PLAN.md |
| Diagnostics from players on any client (`/sr report`, `/sr commtest`, `tools/diag_report.py`) | DONE (mock-tested) |
| External testers and troubleshooting per client | DONE: TESTERS.md, TROUBLESHOOTING.md |
| Project page in English (features, limits, FAQ, bug link, Discord at the bottom) | DONE (text); **real screenshots missing** (taken during the Forever / Classic Era client tests) |
| First Beta: Forever + Classic Era | waiting for the real-client tests (FOREVER.md S1–S7, Classic Era points 1–6) and your GO |

## 4c. One product with stackrivals.io before launch (decided 4 Nov 2026)

The public CurseForge launch of **"StackRivals – Loot Duels"** waits for the website integration:
shared account, XP and level, Shards **display**, rank and season, cosmetics, achievements, results.
The website stays the authority; the addon builds no economy and no reward rules.

| Requirement | Status |
|---|---|
| Integration checklist per point (supported / website delivers / formats / tests / missing / real WoW test) | DONE: `INTEGRATION_CHECKLIST.md` |
| Versioned contracts; newer versions refused with "update" | DONE (SRL1 / SRP1 / SR1; `SRP2` proposed for the Shards display + cosmetics) |
| Waiting for web Claude: agreement of the formats, Link page, `SRP2` decision, signatures, import page, reward rules | WAITING (list in INTEGRATION_CHECKLIST.md) |
| 0.8.1 frozen as the test version (`alpha/0.8.1`); integration work on `feature/web-integration` | DONE (4 Nov) |
| Prepared without new formats: profile view, "Last updated … imported by hand, may be out of date", Shards row only when an approved format fills it; Loot Duel proven independent of Account / Sync | DONE (simulated), 0.9.0 dev |
| Reception process for web Claude's report | DONE: `INTEGRATION_CHECKLIST.md` |
| Integration in the addon (0.9.x) | after the web report; built on the existing account / sync code |
| Joint QA, then Beta / Release | RELEASE_PLAN.md phases 3–4 |

## 5. Out of scope here

* The website and Shards: separate projects.
* A live web connection from WoW (addons have no internet). The Quickplay web adapter stays
  "not connected".
* Gold, bets, and automatic loot.
