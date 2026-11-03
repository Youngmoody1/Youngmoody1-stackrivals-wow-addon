# Handoff to the stackrivals.io project: the WoW addon 0.6.1 integration

For web Claude. Repository `Youngmoody1/Youngmoody1-stackrivals-wow-addon`, branch
`feature/connected`, addon **0.6.1 (development, not released, not tested in a real WoW
client)**. The contract with every field is `docs/STACKRIVALS_WEB_INTEGRATION.md`. This file is
the short version plus the prompt.

## 1. Implemented addon features

| Feature | Status |
|---|---|
| Classic, Time Trial (was Blitz 2:00), Daily Challenge (was Daily Blitz) | BUILT, engine = web parity-tested |
| Spell Battle vs Bot (9 spells, 5 bot levels, the web's survival rule) | BUILT, parity-tested against web code |
| Duels 2:00 / 3:00, Spell Duel (guild, group, friends, Battle.net friends, by name, recent) | BUILT, SIMULATED |
| **Quickplay / Quick Duel** (random rival among reachable searchers) | BUILT, SIMULATED |
| **Character cards** (faction, race, class, level, self-reported) | BUILT, SIMULATED |
| **Match chat** (text within one faction, quick messages, mute, limits) | BUILT, SIMULATED |
| **Account**: link with a one-time code, Pending / Linked / Not synced, Unlink | BUILT addon side; web side missing |
| **Profile** (display of the website's snapshot) | BUILT addon side; web side missing |
| **Sync**: play SR1 challenge codes, export SR1 result codes | BUILT addon side; web import missing |
| Battle.net cross-realm duel transport | text 4/4 (see `docs/CHALLENGE_FRIENDS.md`) |

**WoW-style names** (display only; ids unchanged): Classic, Time Trial, Daily Challenge, Spell
Battle, Duel 2:00 / 3:00, Spell Duel, Quick Duel (QUICKPLAY button) and Guild Duels. The website
may use the same names.

## 2. Shared data formats

* `tools/contract/types.ts` (TypeScript types for every concept):
  * identities: `PlayerRef`, `AccountRef`, `AccountLink`, `Platform`, `MatchId`;
  * rules and logs: `Ruleset`, `GameMode`, `EngineVersion`, `Seed`, `InputLog`, `SpellEvents`;
  * results: `MatchResult`, `MatchVerification`;
  * profiles: `ProfileSnapshot`, `PlayerProfile`, `CharacterProfile`;
  * matchmaking: `MatchmakingStatus`, `MatchmakingEvent`, `MatchInvitation`, `ReadyState`,
    `MatchChatMessage`, `RematchRequest`.
* Wire codes:
  * SR1 (built, agreed by vectors);
  * SRL1 / SRP1 (draft v1);
  * SR2 (draft, not built).

## 3. Quickplay interface and events

Contract §3.

* Native WoW matching is built.
* The web adapter (`status()`, `search()`, `cancel()`) exists and reports `not_connected`.
* Events: `search_started`, `matched`, `ready`, `countdown`, `started`, `result`,
  `rematch_requested`, `search_cancelled`, `no_opponent`, `fell_through`.

## 4. Supported communication channels (WoW side)

| Channel | Used for | Status |
|---|---|---|
| `GUILD` addon broadcast | presence, Quickplay search | SIMULATED |
| `PARTY` / `RAID` addon broadcast | presence, Quickplay search | SIMULATED |
| `WHISPER` addon messages (same / connected realms) | duels, cards, chat, presence | SIMULATED |
| Battle.net addon data (`BNSendGameData`) | duels with Battle.net friends on other realms | text 4/4 |
| WoW chat channels (`SendChatMessage`) | only the player's own "Share score" button | BUILT (by click only) |
| Internet (HTTP / WebSocket) | — | **not available to addons** |

## 5. Real time: what works and what doesn't

* **Real time inside WoW:** duels, Quick Duel, live rival score, spells, chat and shared pauses.
* **No real time between WoW and the website.** WoW ↔ web is asynchronous: same seeds, same
  engine, SR1 codes, and the website's replay.

## 6. Account linking flow

1. The web makes a code `A7K9-P2XJ`.
2. The addon becomes **PENDING** and shows `SRL1…`.
3. The website checks it and binds the character.
4. The website gives `SRP1…`.
5. The addon becomes **LINKED**.

`docs/ACCOUNT_SYNC_HANDOFF.md` §2–3.

## 7. Profile import and export

* **Profile into WoW:** SRP1, display only, newest wins, stale after 7 days.
* **Results out of WoW:** SR1R codes, for challenge runs and today's best Daily run. The `link`
  field holds the `linkId` when linked.

Contract §8–9.

## 8. Match results and verification

* `MatchVerification` is one of `local`, `peer_checked`, `server_verified` or `rejected`.
* Only `server_verified` may rank or reward. That means the website replayed the log
  (`verifyLog`, or `verifySpellMatch` for SR2 later).
* WoW duels stay `peer_checked` and WoW-only.

Contract §10.

## 9. Backend functions the website must provide

1. `createLinkCode(account)` → an 8-symbol Crockford code with a check symbol, single use, about
   10 min, rate-limited.
2. `submitLinkRequest(account, srl1)` → validate, then bind `{accountId, platform, character, linkId}`.
3. `exportProfileSnapshot(account, linkId)` → `SRP1` with `expires` = now + 7 days.
4. `unlink(account, linkId)`.
5. `createChallenge(ruleset)` → an `srchal-…` seed, `SR1C`, `createdAt`, `closesAt`.
6. `importResult(srr1)` → `tools/sr1/sr1.ts` `importResult`: decode, check the challenge,
   `verifyLog`, unique run key, then store. Attribute it to the account only if the `link` matches
   a binding with the same character and platform.
7. A Daily Challenge board for `daily120` (seed `srwow-daily-YYYY-MM-DD`, UTC, closes after 24 h).
8. Rate limits and audit logs for 1–6.

## 10. Shared test vectors and acceptance criteria

* `docs/vectors/sr1.json`: 12 challenge, 32 result and 3 run-key vectors.
  Check: `bun tools/sr1/check_vectors.ts <web checkout> docs/vectors/sr1.json`. 77/77 at web
  `29afe52`.
* `docs/vectors/account_v1.json`:
  * web codes;
  * 3 SRL1 vectors, 14 invalid;
  * 4 SRP1 vectors, 26 invalid.

  Check: `bun tools/contract/check_account_vectors.ts`. 84/84 with the TypeScript reference.
* **Accepted** when:
  * the website's own implementation reproduces both files byte for byte (encode) and verdict for
    verdict (decode and errors);
  * a WoW SR1R code for a website challenge imports as `server_verified`;
  * a forged one is `rejected` with the same reasons as `importResult`.

## 11. Integration blockers

| Blocker | Owner |
|---|---|
| The website has no Link-WoW page, SRL1 check, SRP1 export or unlink | web |
| The website has no SR1 import page, challenge codes or Daily board | web |
| SRL1 / SRP1 and SR2 are drafts: they need the web's agreement (or changes) before "final" | both |
| Profile snapshots aren't signed (`sig` reserved); WoW can't verify where a snapshot came from | web proposes a scheme, then the addon |
| Live WoW ↔ web play or Quickplay: no allowed transport | — (not possible today) |
| Nothing has run in a real WoW client: delivery, throttling, cross-realm and cross-faction whispers, keyboard focus in the chat box, copy and paste in edit boxes | WoW test (you) |
| Web live-loop bug 2 (input after an incoming top-out) | web (`docs/WEB_SPELL_REPORT.md`) |

## 12. Prompt for web Claude (ready to paste)

> You are working in the stackrivals.io project. The WoW addon project (GitHub
> `Youngmoody1/Youngmoody1-stackrivals-wow-addon`, branch `feature/connected`) is ready for the
> website side. Please read these files there:
> `docs/WEB_ADDON_INTEGRATION_HANDOFF.md`, `docs/STACKRIVALS_WEB_INTEGRATION.md`,
> `docs/ACCOUNT_SYNC_HANDOFF.md`, `docs/CROSS_PLATFORM_MULTIPLAYER.md` §6,
> `tools/contract/types.ts`, `tools/contract/account.ts`, `tools/sr1/sr1.ts` and the vectors in
> `docs/vectors/`. Then implement, in the web project only:
>
> 1. **Link WoW character.**
>    * A logged-in page that makes a one-time code (Crockford base32, 8 symbols, the last one a
>      check symbol, single use, about 10 minutes, rate-limited).
>    * A box that accepts the addon's `SRL1` link request, validates it exactly as
>      `tools/contract/account.ts` does, and stores the binding
>      `{accountId, platform, character, linkId, linkedAt}`.
>    * `SRP1` profile snapshots from the website's own profile data (no Shards or currencies),
>      with expires = now + 7 days, shown on confirm and via "Export snapshot".
>    * Unlink, rate limits and an audit log.
> 2. **SR1 challenges and import.**
>    * Create challenges (`srchal-` seeds, `SR1C` codes, `createdAt` / `closesAt`) and a Daily
>      Challenge board (`daily120`, seed `srwow-daily-YYYY-MM-DD`).
>    * An import page for `SR1R` result codes that follows `importResult` in `tools/sr1/sr1.ts`
>      with the real `verifyLog`.
>    * Store `server_verified` or `rejected`.
>    * File a result under an account only when its `link` field (the `linkId` uppercased)
>      matches a stored binding with the same character and platform.
> 3. **Tests.** Unit tests that reproduce `docs/vectors/sr1.json` and
>    `docs/vectors/account_v1.json` exactly, including every error code.
> 4. **Keep the shared names** (types in `tools/contract/types.ts`). If something in the drafts
>    (SRL1 / SRP1 / SR2) doesn't fit the website's account or match model, say so and propose a
>    change before building around it: the formats are drafts until both sides agree.
>
> Rules:
>
> * The website stays the authority for accounts, progression, ranking and rewards. Never trust
>   a WoW summary: only replays.
> * Never ask WoW players for passwords or tokens, and put no secrets in the codes.
> * Don't build a live WoW ↔ web queue: WoW addons have no internet access.
> * Report back with:
>   * what you built;
>   * the vector results;
>   * any format changes you need.
