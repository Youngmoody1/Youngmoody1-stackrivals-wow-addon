# StackRivals WoW addon → stackrivals.io: the one handoff file

* Repository: `Youngmoody1/Youngmoody1-stackrivals-wow-addon`.
* Branch `feature/loot-duel` (addon 0.7.0). It contains everything from `feature/connected` (0.6.1).
* **Start here.** This file is the entry point and the source of truth. The four detail documents
  below are referenced, not repeated, and they agree with this file:

| Detail document | Covers |
|---|---|
| `docs/ACCOUNT_SYNC_HANDOFF.md` | account linking: flow, SRL1 / SRP1 formats, errors, vectors, companion research |
| `docs/STACKRIVALS_WEB_INTEGRATION.md` | the full data contract (12 points), trust boundaries |
| `docs/WOW_QUICKPLAY_HANDOFF.md` | Quickplay, character cards, match chat, names |
| `docs/WEB_ADDON_INTEGRATION_HANDOFF.md` | the backend functions list and acceptance criteria |
| `docs/CROSS_PLATFORM_MULTIPLAYER.md` §6 | SR1 (agreed by vectors) |
| `docs/SR2_DRAFT.md` | SR2 draft (Spell Battle vs Bot results) |

**Nothing has been tested in a real WoW client yet.** All addon tests run in simulated clients.

The 0.7.0 final polish (4 Nov 2026) changed only the addon's own screens. **No format, code or
contract changed**: SR1, SRL1 / SRP1 and the vectors are the same as before.

## 1. Status by category

| Item | Implemented addon side | Ready for web integration | Needs the website to change | Needs a connection we don't have | Needs a real WoW test |
|---|---|---|---|---|---|
| SR1 challenge codes into WoW (play exactly that seed) | ✔ | ✔ (format agreed by vectors) | ✔ challenge creation and a Daily board | — | ✔ copy and paste |
| SR1 result codes out of WoW | ✔ | ✔ | ✔ import page (`importResult`) | — | ✔ copy and paste |
| Account link: web code → SRL1 → SRP1 | ✔ | ✔ draft v1 + vectors + TypeScript reference | ✔ Link page, binding, SRP1 export, unlink | — | ✔ |
| Profile in WoW (SRP1, display only) | ✔ | ✔ draft v1 | ✔ snapshot export | — | ✔ |
| Results attributed to the linked account (`link` = linkId) | ✔ | ✔ | ✔ match the binding (same character and platform) | — | — |
| Signed snapshots (`sig`) | field reserved | ✘ | ✔ propose a scheme | — | — |
| SR2 (Spell Battle vs Bot results) | ✘ (draft only) | ✘ | ✔ agree or change the draft | — | — |
| Quickplay against web players | adapter shows "not connected" | ✘ | — | ✔ (**BLOCKED**: no internet in addons) | — |
| Live WoW ↔ web matches, shared chat | ✘ | ✘ | — | ✔ **BLOCKED** | — |
| WoW duels, Quick Duel, chat, Battle.net, Loot Duel | ✔ (WoW only) | not meant for the web | — | — | ✔ |
| Optional companion app (fewer copy and paste steps) | research only | ✘ | maybe an API | ✔ needs approval and a rules check | — |

## 2. Formats

| Format | State | Files | Vectors |
|---|---|---|---|
| SR1C / SR1R | **agreed** (the TypeScript reference passes with the web's real `verifyLog`: 77/77 at web `29afe52`) | `StackRivals/Net/Codes.lua`, `tools/sr1/sr1.ts` | `docs/vectors/sr1.json` |
| Web link code, SRL1, SRP1 | **provisional DRAFT v1** | `StackRivals/Net/AccountCodes.lua`, `tools/contract/account.ts` | `docs/vectors/account_v1.json` (84/84 Lua = TypeScript) |
| SR2 | **draft, not built** | `docs/SR2_DRAFT.md` | — |
| Shared types (PlayerRef, AccountRef, Platform, MatchId, Ruleset, GameMode, EngineVersion, Seed, InputLog, SpellEvents, MatchResult, MatchVerification, ProfileSnapshot, …) | **provisional v1** | `tools/contract/types.ts` (type-checked) | — |
| WoW addon protocol (duels, Quickplay, cards, chat, Loot Duel) | WoW only | `StackRivals/Net/Protocol.lua` | addon tests |

Compatibility rules:

* Every code starts with its format and version.
* A newer version is refused with "update", never guessed.
* An existing version never gets new fields.
* The engine version is part of every result.
* Unknown or non-canonical values are refused.

## 3. Flows

1. **Link.**
   1. The website (logged in) shows the code `A7K9-P2XJ`.
   2. The addon becomes PENDING and shows `SRL1…`.
   3. The website checks and binds `{accountId, platform, character, linkId}`.
   4. The website shows `SRP1…`.
   5. The addon becomes LINKED.

   A typed code alone is never Linked. Details: `ACCOUNT_SYNC_HANDOFF.md` §2–3.
2. **Profile.** The website gives `SRP1` ("Export snapshot"). The addon shows it as display only.
   The newest one wins, and it counts as NOT SYNCED after 7 days.
3. **Challenge.** The website creates `SR1C` (an `srchal-…` seed, `createdAt`, `closesAt`). WoW
   plays exactly that seed and exports `SR1R`. The website runs `importResult`: decode, check the
   challenge, `verifyLog`, run key, then store.
4. **Daily Challenge.** `daily120`, seed `srwow-daily-YYYY-MM-DD` (UTC). WoW exports today's best
   run.

## 4. Security and trust (both projects)

* There are no passwords, e-mails, tokens or secrets in WoW or in any code.
* Only the website's replay can make a result `server_verified`, and only `server_verified` may
  rank or reward.
* WoW duels and Loot Duels are `peer_checked` and stay in WoW.
* These are **claims** until the website matches them to its own records:
  * the WoW character name (in a pasted code);
  * the faction, race, class and level;
  * the profile snapshot;
  * the `linkId`.
* Battle.net `gameAccountID`s are temporary. They are never stored or used as an identity.
* No Shards, currencies, gold, bets or rewards in the addon.

## 5. What the website builds (functions + acceptance)

1. `createLinkCode` (Crockford, check symbol, single use, ~10 min, rate-limited).
2. `submitLinkRequest(SRL1)` → binding.
3. `exportProfileSnapshot` → `SRP1`, expires in 7 days.
4. `unlink`.
5. `createChallenge` → `SR1C`.
6. A Daily board for `daily120`.
7. `importResult(SR1R)` = `tools/sr1/sr1.ts`.
8. Rate limits and an audit log.

**Accepted when:**

* both vector files reproduce byte for byte (encode) and error for error (decode);
* a real WoW `SR1R` for a website challenge imports as `server_verified`;
* a forged one is `rejected` with `importResult`'s reasons;
* a WoW character links and unlinks with a code.

## 6. Open blockers

| Blocker | Owner |
|---|---|
| Link page, SRL1 check, SRP1 export, unlink | web |
| SR1 import page, challenge codes, Daily board | web |
| Agree SRL1 / SRP1 (and SR2) or propose changes | web + you |
| Snapshot signatures | web proposes, then the addon checks |
| Web live-loop bugs: the final tick at the cap, and input after an incoming top-out (`docs/WEB_SPELL_REPORT.md`) | web |
| Live web ↔ WoW play | not possible today |
| Every real WoW client test (`docs/INSTALL_AND_TEST.md`) | you |

## 7. Prompt for web Claude (ready to paste)

> You are working in the stackrivals.io project. The WoW addon (GitHub
> `Youngmoody1/Youngmoody1-stackrivals-wow-addon`, branch `feature/loot-duel`) is ready for the
> website side. Read `docs/WEB_HANDOFF.md` there first. It is the single entry point and links to
> everything else: the account formats in `docs/ACCOUNT_SYNC_HANDOFF.md`, the contract in
> `docs/STACKRIVALS_WEB_INTEGRATION.md`, the types in `tools/contract/types.ts`, the TypeScript
> references `tools/contract/account.ts` and `tools/sr1/sr1.ts`, and the vectors in
> `docs/vectors/`. Then implement, in the web project only:
>
> 1. **Link WoW character.** A one-time code, SRL1 validation and binding, SRP1 snapshots (no
>    Shards or currencies, expires in 7 days), unlink, rate limits and an audit log.
> 2. **SR1.** Challenge creation (`srchal-` seeds), a Daily Challenge board (`daily120`), and an
>    `SR1R` import that follows `importResult` with the real `verifyLog`. File a result under an
>    account only when its `link` matches a binding with the same character and platform.
> 3. **Tests.** Unit tests that reproduce `docs/vectors/sr1.json` and
>    `docs/vectors/account_v1.json` exactly.
> 4. **Report back.** Anything in the drafts (SRL1 / SRP1 / SR2) that doesn't fit, before
>    building around it, and propose a snapshot signature scheme if you want one.
>
> Rules:
>
> * The website stays the authority; trust only replays.
> * No passwords, tokens or secrets in WoW codes.
> * No live WoW queue: addons have no internet access.
> * Don't change the formats without saying so.
>
> Report: what you built, the vector results, and any format changes.
