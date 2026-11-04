# StackRivals WoW addon: status of every feature (0.7.0, 4 Nov 2026)

How to read the status words:

* **BUILT** — in the addon, wired to the real gameplay, covered by automatic tests.
* **SIMULATED** — the automatic tests use simulated WoW clients (`tests/netsim.lua`, a WoW API
  mock). **No feature below has run in a real WoW client yet.**
* **PROPOSED** — a format or contract that waits for stackrivals.io to agree.
* **BLOCKED** — not possible today with allowed, documented means.

Automatic tests are **not** real client tests. Real client tests are tracked in
`docs/INSTALL_AND_TEST.md` (all marked NOT TESTED until you run them).

## Builds

| Build | Branch | Content | Status |
|---|---|---|---|
| 0.3.1 | `release/0.3.1` | Classic, Blitz (now Time Trial), Daily | stable candidate, unchanged |
| 0.5.1 vs Bot | `spellbattle` | + Spell Battle vs Bot (the web's survival rule) | test build, unchanged |
| 0.6.0 | `multiplayer` | + Challenge Friends | development, unchanged |
| 0.6.1 | `feature/connected` | + Quickplay, cards, chat, account, sync, Battle.net | development, unchanged |
| **0.7.0** | `feature/loot-duel` | 0.6.1 + review fixes + WoW colours + Loot Duel | development (this one) |

## Features

| Feature | Wired to | Status | Real WoW test needed for | Known limits |
|---|---|---|---|---|
| Classic, Time Trial, Daily Challenge | engine (bit-exact parity with the web) | BUILT | loading, keys, combat pause | — |
| Spell Battle vs Bot | the web's spells, bot and survival rule | BUILT (parity-tested against web code) | performance, keys Q/E/R/F | two web live-loop bugs open (web side) |
| Duel 2:00 / 3:00, Spell Duel | duel protocol, peer replay, verdict exchange | BUILT, SIMULATED | delivery and throttling between two clients | peer-checked, not server-verified |
| Guild Duels lists (guild, friends, Battle.net, group, recent, by name) | the client's rosters, presence via HEL/HI | BUILT, SIMULATED | the roster APIs, connected realms | — |
| Battle.net transport (other realms) | `C_BattleNet.SendGameData` / `BN_CHAT_MSG_ADDON` | BUILT, SIMULATED | **whether it delivers** in Classic Era 1.15.9 and Forever 1.60.1, order, rate | Battle.net friends only, same WoW version |
| Quickplay / Quick Duel | QS search, INV `q`, the duel lobby as ready check | BUILT, SIMULATED | guild / party / friend reach, timing | no global queue; web adapter "not connected" (BLOCKED) |
| Character cards | `UnitFactionGroup/Race/Class/Level` + PRF | BUILT, SIMULATED | the APIs, emblem and portrait textures | the rival's data is self-reported |
| Class and faction colours | `C_ClassColor` → `RAID_CLASS_COLORS` → official values | BUILT | the colours match the raid frames | race has no official colour (by design) |
| Match chat | CH / QM whispers or Battle.net | BUILT, SIMULATED | **cross-faction delivery**, keyboard focus while typing | text within one faction only (or over Battle.net) |
| Account link (one-time code) | SRL1 / SRP1 copy and paste | BUILT addon side, PROPOSED formats | copy and paste in WoW edit boxes | needs the website's Link page (missing) |
| Profile (rank, level, XP, season, history) | the SRP1 snapshot, display only | BUILT addon side | — | no signature check yet; the website is the authority |
| Sync: play challenge codes, export results | SR1C / SR1R (vector-checked with the web) | BUILT addon side | copy of 2–3 KB codes in WoW | needs the website's SR1 import (missing) |
| Loot Duel | LD* group messages, peer replay on every PC | BUILT, SIMULATED (0.7.0) | raid channel load, 20–40 players, timing | peer-checked; never touches loot |
| Web Quickplay / live web ↔ WoW | — | BLOCKED | — | addons have no internet access |
| Shards | — | not built (web project) | — | — |

## Review of 0.6.1 (independent, 3–4 Nov 2026)

Six confirmed problems. All are fixed in 0.7.0, with regression tests in `tests/test_review.lua`.

1. A chat line that wrapped could split an escaped `||` and inject colour codes. Fixed: wrap first,
   then escape; never cut inside a UTF-8 character.
2. "Play again" on a web challenge after `/reload` used a random seed and exported it. Fixed: the
   challenge is rebuilt; challenge, loot and duel modes can't be started as solo modes.
3. Quickplay kept searching while you were in a normal duel. Fixed: the search stops.
4. WoW Forever was reported as `wow-classic`, because of `a and f()` truncating return values.
   Fixed with `select(4, GetBuildInfo())`. The same bug was found and fixed twice more in Loot Duel.
5. "Share my card" off still sent the duel record. Fixed.
6. The Sync tab could only reach 3 of 10 results. Fixed with paging.

Plausible issues, also fixed:

* Quickplay invites now require the sender's own QS.
* Expired one-time codes are dropped on load.
* A Battle.net friend without a realm is never guessed onto yours.
* Forced friend-list re-reads are limited.
* Cards are re-sent until the rival's arrives.
* Older rivals are shown as "older StackRivals".

Kept as documented limits (not fixable in the addon):

* The faction claim and the profile snapshot are self-made data.
* The website must never trust them.

## Test counts

`lua5.1 tests/run.lua`, run in GitHub CI on every push. The numbers per file are in the CI log.
Totals:

* 0.6.0: 482
* 0.6.1: 562
* 0.7.0: see the latest CI run on `feature/loot-duel`; the final count is in the delivery note.

## Open blockers

See `docs/WEB_HANDOFF.md` §6 (web) and `docs/INSTALL_AND_TEST.md` (real client).
