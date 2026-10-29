# Keeping web and WoW in sync

**stackrivals.io is the source of truth for gameplay rules.** The WoW addon is a separate Lua
implementation of the same rules. No code is copied automatically: TypeScript and Lua differ, and
silent automatic updates would be fragile. What *is* automated is the **comparison**.

## Current base

| | |
|---|---|
| Web repo | `Youngmoody1/stackrivals-practice-arena` (read-only from this project) |
| Web commit the addon matches | `29afe520d483539a3bc83417c542bf43fffae874` (29 Oct 2026) — stored in `tests/fixtures/parity.lua` |
| Engine version | `ENGINE_VERSION = 1` on both sides |
| Verified by | rules fingerprint (every constant, incl. the 1v1 match rules and `CLOCK_SLACK_MS`) + 66 replayed games + PRNG vectors + Daily sequences, all equal |
| Shared codes | SR1 vectors (`docs/vectors/sr1.json`): TS reference + the web's real `verifyLog` reproduce all 57 checks |

The engine code has not changed on the web between `5bb25f2` (the original port) and `29afe52`
(the commits after `5d2a9fd` are layout/QA only).

## How a web change is detected

```
tools/parity/check_web.sh ../stackrivals-practice-arena
```

1. Prints the base commit and the web HEAD, lists web commits since the base that touch gameplay
   (`src/game/engine`, `src/game/controls.ts`, `src/game/bot`, `src/lib/match/rules.ts`) and shows
   whether `ENGINE_VERSION` changed.
2. Generates fresh fixtures from the web checkout and runs the Lua engine tests against them:
   - **Rules fingerprint**: compares each constant on its own and names it when it differs,
     e.g. `linePoints.4: web 1000 / lua 800` or `config.lockDelayTicks: web 25 / lua 30`.
     It covers the board size, hidden rows, preview count, lock delay and resets, lines per level,
     line points, back-to-back, combo, drop points, the speed curve (levels 1–25), DAS/ARR,
     action list, piece ids, every piece rotation and every wall-kick table, and the web 1v1 match
     constants (time cap, countdown, input-rate limits).
   - **Behaviour**: 66 games (web bots at 5 difficulties, a quad-seeking bot, 40 fuzz scripts)
     replayed in Lua must reach the exact same `hashState`, score, lines, level, piece count and
     game-over at three checkpoints each.
   - **Piece generation**: PRNG vectors and the first 14 Daily Blitz pieces for fixed dates.
3. Checks the SR1 cross-platform code vectors with `tools/sr1/check_vectors.ts`: the TypeScript
   reference decoder plus the web's real `verifyLog` must reproduce every expectation the Lua
   addon generated (decode errors, replayed score, hash, rejection reasons in order).
4. PASS means nothing to port. FAIL lists exactly what to port.

## Porting procedure (reviewed, never automatic)

1. Run the checker and read the failing lines plus the web commit diff.
2. Classify each change:
   - **Must port**: anything in the fingerprint or behaviour tests (rules, scoring, pieces, speed, kicks, game over).
   - **Adapt for WoW**: new modes, UI/visual changes, animations, input feel.
   - **Not relevant**: SEO, site pages, payments, wallet, accounts UI.
   - **Bigger project**: new systems (ranked, seasons, spells, multiplayer).
3. Port to Lua and add a test for the new behaviour.
4. If the web bumped `ENGINE_VERSION`, bump it in `Engine.lua` too. Records saved under the old
   rules are then **archived automatically** (`db.archive["rules<N>"]`, never deleted), and new
   records start fresh. Old scores stay viewable and are never mixed with the new ones.
5. Regenerate fixtures to move the base: `bun tools/parity/gen-fixtures.ts <web> > tests/fixtures/parity.lua`.
6. Run all tests and the build, bump the addon version, and add a CHANGELOG line ("rules synced with web commit …").

## What the WoW addon implements (web features at `5d2a9fd`)

| Web feature | WoW addon | Notes |
|---|---|---|
| Engine: 7 pieces, 7-bag, SRS-style kicks, hold, 5-piece preview, ghost, lock delay, scoring, combos, B2B, levels | ✅ identical | Parity-tested |
| DAS/ARR input feel | ✅ identical | `Input.HANDLING` fingerprinted |
| Practice (solo, endless) | ✅ as **Classic** | Same rules |
| Timed score run | ✅ **Blitz 2:00** | WoW-only mode length (web 1v1 cap is 3:00) |
| Same-seed daily run | ✅ **Daily Blitz** | WoW-only. The web's "daily challenges" are XP tasks, not a shared-seed run |
| Replays from input logs | ◐ data only | Best runs are stored in the web log format; no replay viewer in WoW |
| vs Bot (5 difficulties) | ❌ not yet | The bot is deterministic TS; could be ported later |
| Quick Match / Direct Challenge (1v1 score race, shared seed, 3:00 cap) | ◐ WoW duels (branch `multiplayer`) | Guild/party/whisper duels; ruleset `r180` = web 1v1 cap + countdown; peer-checked, not server-verified. See docs/CROSS_PLATFORM_MULTIPLAYER.md |
| Spell Battle (mana, 9 spells) | ❌ | Bigger project; its engine module is separate on the web |
| Server verification, fraud checks | ❌ | No internet from WoW; local results are labelled unverified |
| Ratings, ranks, seasons, leaderboards | ❌ | Needs verified results |
| XP, levels, skill tree, daily XP challenges | ❌ | Web account system |
| Block skins (Circuit default) | ◐ Circuit only | Colours converted from the web's oklch values |
| Victory effects, VFX, sounds | ◐ adapted | Flash, callouts, own synthesized sounds (same recipes as the web) |
| Chat, spectate, tournaments, shop, Pro | ❌ not relevant / not allowed | The addon must stay free (Blizzard policy) |

## What we need from the web project when its optimisation is done

Ask the web Claude for a short **change report**:

```
StackRivals web – change report for the WoW addon
Range: <old commit>..<new commit>   ENGINE_VERSION: <old> -> <new>
1. Gameplay rule changes (engine/controls): what, why, commit
2. New or changed modes (rules, time limits, seeds)
3. Match / 1v1 rule changes (src/lib/match/rules.ts constants, winner rules, verification)
4. Visual identity changes (colours, logo, skins, fonts) with values
5. Features intentionally web-only
6. Anything that changes how scores compare across versions
```

The WoW side then runs `check_web.sh`, which verifies the report against the code.
