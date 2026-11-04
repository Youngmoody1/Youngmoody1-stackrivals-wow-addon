# Release plan: CurseForge Alpha → Beta → Release (from 0.8.1)

Goal: **one StackRivals project on CurseForge** for every official WoW client, with one universal
ZIP. Clients are added to each file's **game versions only as far as their tests allow**. Nothing is
uploaded or published without your explicit **GO**.

The addon is and stays **free**: no ads, no paid or locked features, no donation prompts in the game.
It contains no Shards and no web purchases. That is also Blizzard's AddOn policy.

## 1. The three channels

| Channel | What it is for | Who sees it | Needed before it |
|---|---|---|---|
| **Alpha** | Internal builds for us and named testers | CurseForge website; app users only if they opt in to Alpha | CI green; owner GO |
| **Beta** | Public test build for the clients whose basics are checked | Website, and app users who opt in to Beta | the **Beta GO list** (§3) for each client tagged |
| **Release** | The stable build that the CurseForge app installs and updates by default | Everyone | the **Release GO list** (§4) for each client tagged |

A client can be in a Beta while still being "mock-tested only". It is then labelled as such in
the description (§5). It is **never** called verified on the strength of a mock test.

## 2. Status words (the same everywhere: here, COMPATIBILITY.md, the CurseForge page)

* **Simulated / mock-tested:** automated tests pass against a model of that client's API. This
  proves logic and fallbacks, not the client.
* **Client-tested (solo):** loading, every solo mode, input, combat pause and saved data were checked
  in that real client.
* **Client-tested (multiplayer):** duels and/or Loot Duel between real players on that client.
* **Not verified:** none of the above yet.

## 3. Beta GO / NO-GO (per client, per build)

| # | Check | How |
|---|---|---|
| B1 | All automated tests green on Lua 5.1 for the exact commit | GitHub CI run linked in the upload notes |
| B2 | No known critical Lua error | open issues and test logs |
| B3 | The ZIP equals the commit (`git archive`), and the SHA-256 is recorded | `tools/build_release.sh` (verify step) |
| B4 | The TOC interface list equals the live clients (`tools/clients.json`) | `tools/validate_addon.py` |
| B5 | **The client loads it**: AddOns list, `/sr version`, `/sr report` | at least one real client of the Beta's **primary** clients (Forever or Classic Era) |
| B6 | Solo gameplay and input work in that client (Classic, Time Trial, Daily, Spell Battle; keys; combat pause; `/reload` keeps the run) | the same real client |
| B7 | Saved data survives the upgrade from the installed version | real client (e.g. 0.7.0 → 0.8.1 in Classic Era) |
| B8 | Version-specific limits documented and shown on the page (§5) | COMPATIBILITY.md |
| B9 | Multiplayer features carry their real status on the page | "not verified yet" until §4 R7 is done |
| B10 | No known exploit or critical bug in Loot Duel | LOOT_DUEL.md trust limits; open issues |
| B11 | No promise of global / web matchmaking | description review |
| B12 | Game versions on the upload = only the clients that pass B5–B7, plus clients named "mock-tested" in the text if you decide so | upload checklist |
| B13 | **Your GO**, written | – |

A client that fails B5–B7 is **left off** that upload. That never blocks the others.

## 4. Release GO / NO-GO (per client)

Everything in §3, plus:

| # | Check |
|---|---|
| R1 | A Beta of the same code has been public for at least a few days with no open crash or Lua-error report for that client |
| R2 | Gameplay and input tested in **that** real client (not only another client of the same family) |
| R3 | Saved data and upgrade tested in that client |
| R4 | `/sr report` from that client shows the expected client type, interface and APIs |
| R5 | Its API limits are documented (COMPATIBILITY.md) and handled in code (lockdown, trial accounts, removed globals) |
| R6 | **Multiplayer** (Quickplay, Guild Duels, Battle.net, Match Chat, Loot Duel) is announced as supported on a client **only after a test with real players on that client**. For Loot Duel that means at least 5 players. For "up to 40", a real raid (LOOT_DUEL.md R6). Until then the page says "not verified on this client yet" |
| R7 | For Forever: FOREVER.md F1–F3 done. That covers the live interface number, delivery in the open world and in a dungeon between pulls, and the boss-fight lockdown |
| R8 | Correct game-version tags on CurseForge |
| R9 | **Your GO** |

## 5. Readiness today (4 Nov 2026, build 0.8.1)

| Client | Automated | Real client | Beta-ready? | Missing for Release |
|---|---|---|---|---|
| **WoW Forever** | mock profile + multiplayer simulations green | **nothing yet** (client installed on your PC: 1.60.1.70755) | **after S1–S7** (FOREVER.md): live interface, load, solo play | F1–F3 (delivery in dungeons), loot methods, 5-player Loot Duel |
| **Classic Era** (incl. Hardcore, SoD realms) | green | 0.3.1 smoke test OK; 0.7.0 installed, its test not done | **after the 0.7.0 test points 1–6 pass on 0.8.1** (TEST_LOG_CLASSIC_ERA.md) | multiplayer with real players; Hardcore and SoD realms each loaded once |
| Retail (Midnight) | green | not tested (your client needs an update) | later: needs one real load + solo pass | the same |
| TBC Anniversary | green | not tested (your client needs an update) | later: needs a tester or your client | the same |
| Mists Classic | green | not tested (not installed) | later: external tester | the same |
| Titan Reforged | green (older API model) | no access (China only) | not planned as a tagged version: we can't test it | a tester in China |

**Safe first public release:**
1. **Beta for Forever + Classic Era**, as soon as S1–S7 (Forever) and the solo points (Classic Era)
   pass on the same build.
2. Then **Release for those two**, after R1–R7.
3. Retail, TBC Anniversary and Mists are added to later uploads of the same project as soon as
   each passes B5–B7 (an external tester is enough, see `docs/TESTERS.md`).
4. The compatibility code for all of them stays in every build.

## 6. Versions

| Version | Content | Channel |
|---|---|---|
| 0.8.1 | universal build, client layer, `/sr report`, `/sr commtest` | Alpha (now, internal) → Beta after §3 |
| 0.8.x | fixes from the first Forever and Classic Era client tests | Beta |
| 0.9.0 | first public Release for Forever + Classic Era (solo verified; multiplayer marked by real status) | Release |
| 1.0.0 | multiplayer verified with real players on Forever and Classic Era; more clients tagged | Release |

Version numbers: `## Version` in the TOC = the CHANGELOG's top entry = the CurseForge display name
`StackRivals 0.8.1`. Pre-releases may add `-beta1` to the display name only. The validator keeps
TOC and CHANGELOG in step.

## 7. Fallbacks

* **Forever's live interface ≠ 16001:** one line in `tools/clients.json` and the TOC, rebuild.
  Until then players can tick "Load out of date AddOns".
* **A client changes an API we use:** it can only hit the client layer or UI. Patch behind a
  feature check, then release 0.8.x.
* **Forever blocks addon messages in whole dungeons (F2):** Loot Duel inside Forever dungeons
  becomes "unsupported" on the page. The addon already refuses with the "this zone" reason, and
  Loot Duel still works outside instances and in raids between pulls, if those allow it.
* **CurseForge review is slow:** the GitHub release ZIP plus the install guide.
