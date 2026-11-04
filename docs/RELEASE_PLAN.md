# Release plan: "StackRivals – Loot Duels" on CurseForge (revised 4 Nov 2026)

Goal: **one project, "StackRivals – Loot Duels"**, for every official WoW client, with one universal
ZIP. The addon and stackrivals.io launch as **one product**: the same account, progression and
rewards, with the website as the authority. Clients are added to each file's game versions **only
as far as their tests allow**. Nothing is uploaded or published without your explicit **GO**.

## 0. Phases (decided 4 Nov 2026)

| Phase | Version | What | Channel | Gate to the next phase |
|---|---|---|---|---|
| 1. Addon ready | **0.8.1** (now) | Internal Alpha; real-client tests on Forever and Classic Era (FOREVER.md, TEST_LOG_CLASSIC_ERA.md); fixes | internal only (your PC, named testers); **not on CurseForge** | Forever S1–S7 and F1–F3, Classic Era 1–6 passed; no critical Lua error |
| 2. Integration | **0.9.x** (next) | Fixes from phase 1 + the website's contracts (`docs/INTEGRATION_CHECKLIST.md`): linking, profile with XP, level, Shards display, rank and season, cosmetics, achievements, results | internal Alpha builds | contracts agreed in writing; web vectors pass in CI; import / export tested |
| 3. Joint QA | 0.9.x → **1.0.0-beta** | Full journey on real clients: link → play in WoW → export → website imports and verifies → profile back in WoW. Plus multiplayer with real players (Loot Duel with 5, then a raid) | **Beta** on CurseForge, only after your GO, tagged only with the clients that passed | §3 Beta GO list |
| 4. Launch | **1.0.0** | Stable release after full QA, docs and your approval | **Release** | §4 Release GO list |

**Frozen test version (4 Nov 2026):** branch `alpha/0.8.1` at `2d1bd44` is the fixed reference
for every phase 1 test. It gets no code changes.

| Field | Value |
|---|---|
| Version | `## Version: 0.8.1` |
| Interfaces | 16001, 11509, 120105, 20506, 50504, 38002 (= `tools/clients.json`) |
| Addon code | `ae4c7f5` |
| ZIP | `StackRivals-0.8.1-alpha.zip`, 82 files, equal to `git archive 2d1bd44 StackRivals` |
| SHA-256 | `27fbb470f81c2a16ea106ba3a2a2aff43c86b777254596f0c4c611a611d7ea95` (the same on every rebuild) |
| CI | green on `9176b8d`, `be664df`, `2d1bd44` (753 tests, Lua 5.1) |

A bug found in a real client is fixed on `feature/web-integration` (0.9.x) with a regression test.
Only a critical bug that blocks the test would get a `0.8.2` from `alpha/0.8.1`, and only with your
approval.

**Why no public version earlier:** a public stable build that later needs its account, XP, Shards
or profile reworked would break players' saved data and trust. Internal builds may go out at any
time.

The addon is and stays **free**: no ads, no paid or locked features, no donation prompts in the game.
It contains no Shards and no web purchases. That is also Blizzard's AddOn policy.

## 1. The three channels

| Channel | What it is for | Who sees it | Needed before it |
|---|---|---|---|
| **Alpha** | Internal builds for us and named testers (phases 1–2). Shared directly as a ZIP, **not uploaded** to CurseForge | you and named testers only | CI green |
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
| B13 | The integration features this Beta announces are agreed and tested (none are announced before that) | INTEGRATION_CHECKLIST.md |
| B14 | **Your GO**, written | – |

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
| R9 | **Integration:** the contracts are agreed; XP, Shards display, profile and linking are integrated; import and export are tested end to end with the real website (`docs/INTEGRATION_CHECKLIST.md`) |
| R10 | No unverified WoW result gives a valuable reward. No paid web subscription or purchase is needed for any addon feature |
| R11 | **Your GO** for this exact build (version, commit, SHA-256) |

## 5. Readiness today (4 Nov 2026, build 0.8.1)

| Client | Automated | Real client | Beta-ready? | Missing for Release |
|---|---|---|---|---|
| **WoW Forever** | mock profile + multiplayer simulations green | **nothing yet** (client installed on your PC: 1.60.1.70755) | client part: **after S1–S7** (FOREVER.md); then phase 2–3 | F1–F3 (delivery in dungeons, **2+ players**), loot methods, 5-player Loot Duel, integration |
| **Classic Era** (incl. Hardcore, SoD realms) | green; a save written by 0.7.0 itself upgrades cleanly (test) | 0.3.1 smoke test OK; 0.7.0 installed, its test not done | client part: **after test points 1–6 pass on 0.8.1** (TEST_LOG_CLASSIC_ERA.md); then phase 2–3 | multiplayer with real players; Hardcore and SoD realms each loaded once; integration |
| Retail (Midnight) | green | not tested (your client needs an update) | later: needs one real load + solo pass | the same |
| TBC Anniversary | green | not tested (your client needs an update) | later: needs a tester or your client | the same |
| Mists Classic | green | not tested (not installed) | later: external tester | the same |
| Titan Reforged | green (older API model) | no access (China only) | not planned as a tagged version: we can't test it | a tester in China |

**Safe first public release:**
1. **Beta (1.0.0-beta) for Forever + Classic Era**, after:
   * their client tests;
   * the agreed website integration (phase 2);
   * the joint QA (phase 3).
2. Then **Release for those two**, after R1–R10.
3. Retail, TBC Anniversary and Mists are added to later uploads of the same project as soon as
   each passes B5–B7 (an external tester is enough, see `docs/TESTERS.md`).
4. The compatibility code for all of them stays in every build.

## 6. Versions

| Version | Content | Channel |
|---|---|---|
| 0.8.1 | universal build, client layer, `/sr report`, `/sr commtest` | internal Alpha (now) |
| 0.8.x | fixes from the first Forever and Classic Era client tests | internal Alpha |
| 0.9.x | the website's integration (contracts agreed first) + fixes | internal Alpha |
| 1.0.0-beta | joint QA passed on the clients tagged | **Beta** (first public file), after your GO |
| 1.0.0 | stable: everything in §4 | **Release**, after your GO |

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
