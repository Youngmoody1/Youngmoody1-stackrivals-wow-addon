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

**No addon feature has been tested in a real WoW client yet** (only the 0.3.1 smoke test and one
observation, the Spell Battle red box). All addon tests run in simulated clients.

The 0.7.0 final polish (4 Nov 2026), 0.7.1 (Loot Duel for 2–10 players) and 0.7.2 (Loot Duel
for 2–40 players, result screens; branch `feature/loot-duel-raid`) changed only the addon's own screens and its WoW-only Loot Duel
messages. **No format, code or contract for the website changed**: SR1, SRL1 / SRP1 and the
vectors are the same as before. Loot Duel stays in WoW (peer-checked, never on the website).

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

Self-contained: it works even if web Claude can only read what is pasted. The repository is
public, so the links below can also be opened directly. Copy everything inside the box.

````text
You are working in the stackrivals.io web project (Lovable). Your job: build the WEBSITE side of
the integration with the StackRivals World of Warcraft addon. The addon side is finished and
tested in simulated clients (615 automatic tests); it has not been tested in a real WoW client yet.

=== 0. Hard rules ===
- Change only the web project. Do not build Shards, currencies, gold, bets or rewards for WoW.
- The website is the only authority for accounts, progression, rankings and results.
- A WoW addon has NO internet access. Everything between WoW and the website moves as text codes
  the player copies and pastes. Do not build or promise a live WoW queue, live WoW<->web matches or
  shared live chat: that needs a transport that does not exist.
- No passwords, e-mails, session tokens or secrets may ever appear in a code or be asked for in WoW.
- Trust only your own server-side replay. Everything inside a pasted code is a claim.
- Do not change a format silently. If something below doesn't fit the web project, stop and report
  it before building around it.

=== 1. Sources (public; read them if you can, they are the reference) ===
Main handoff:            https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/docs/WEB_HANDOFF.md
Account formats:         https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/docs/ACCOUNT_SYNC_HANDOFF.md
Integration contract:    https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/docs/STACKRIVALS_WEB_INTEGRATION.md
SR1 spec (section 6):    https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/docs/CROSS_PLATFORM_MULTIPLAYER.md
Quickplay/cards/chat:    https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/docs/WOW_QUICKPLAY_HANDOFF.md
SR2 draft:               https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/docs/SR2_DRAFT.md
Shared TypeScript types: https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/tools/contract/types.ts
Account TS reference:    https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/tools/contract/account.ts
SR1 TS reference:        https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/tools/sr1/sr1.ts   (no imports; you may copy it)
Test vectors:            https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/docs/vectors/account_v1.json
                         https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/loot-duel/docs/vectors/sr1.json
If you can't open these, ask the user to paste tools/sr1/sr1.ts, tools/contract/account.ts and
the two vector files. Your implementation must reproduce both vector files exactly.

Common rules for every code:
- Fields are separated by "."; the last field is <check> = 8 lowercase hex digits of FNV-1a 32
  over everything before ".<check>" (the web engine's hashString; codes are ASCII). It only
  catches typos. It is NOT security.
- b36 = lowercase base 36, canonical (no leading zeros, "0" for zero). hex = lowercase hex of
  UTF-8 bytes.
- Remove ASCII whitespace before decoding (pasted codes get wrapped). Refuse anything else outside
  printable ASCII, wrong field counts, non-canonical numbers and unknown versions. Never "best
  effort". A newer version is refused with "update", never guessed.
- platform is one of: wow-forever | wow-retail | wow-classic.
- Character names travel as playerHex = hex of "Name-Realm" (realm without spaces or hyphens).

=== 2. Account linking (DRAFT v1; the addon is built) ===
Flow:
1. Logged-in web user: Account > Link WoW character -> show a one-time code like A7K9-P2XJ.
2. Player types it in WoW (Account tab). The addon goes PENDING (never "linked" from a typed code)
   and shows an SRL1 link request.
3. Player pastes SRL1 on the website. You check it and store a binding
   { accountId, player "Name-Realm", platform, linkId, linkedAt }, and mark the code used.
4. You show an SRP1 snapshot. The player pastes it in WoW -> the addon goes LINKED.
5. Unlink on the website (and the addon has its own Unlink, which only forgets the link locally).

Web link code: 8 symbols of Crockford base32 "0123456789ABCDEFGHJKMNPQRSTVWXYZ", shown XXXX-XXXX.
Symbols 1-7 from a CSPRNG; symbol 8 = (sum of value(s_i)*(2i-1) for i=1..7) mod 32.
Single use, ~10 minutes, bound to the logged-in account, rate-limited (e.g. 5 per hour).
(The addon ignores case, spaces and "-", and reads O->0, I/L->1.)

SRL1 (addon -> website):
  SRL1.<code8>.<platform>.<playerHex>.<linkId>.<addon>.<engine>.<issued36>.<check>
  code8   = the web code without the dash (check symbol valid)
  linkId  = 12 [a-z0-9], random per request, made by the addon (public, not a secret)
  addon   = addon version with "-" (e.g. 0-7-0); engine = ENGINE_VERSION (decimal, currently 1)
  issued36 = unix seconds (b36) when the code was typed
Website checks: format + check; the code exists, belongs to the logged-in account, is unused and
not expired; then store the binding and consume the code.

=== 3. Profile sync: SRP1 (website -> addon, display only in WoW) ===
  SRP1.<linkId>.<playerHex>.<accountId>.<nameHex>.<issued36>.<expires36>.<level36>.<xp36>
      .<xpNext36>.<rankHex>.<seasonHex>.<seasonPct>.<w36>.<l36>.<d36>.<history>.<ach>.<cos>.<sig>.<check>
  linkId     = the linkId of the binding (every later snapshot repeats it)
  playerHex  = the linked character (the addon refuses a snapshot for another character)
  accountId  = 4-40 [a-z0-9_-], your PUBLIC account ref (never an e-mail, never secret)
  nameHex    = display name, 1-32 bytes UTF-8, no control characters
  issued/expires = unix s, expires > issued, at most 30 days later (use 7 days)
  level <= 9999, xp <= 10^12, xpNext "0" = unknown
  rankHex / seasonHex = "-" or 1-24 bytes UTF-8; seasonPct = 0-100 decimal
  w / l / d  = b36 <= 10^9, the website's own counts
  history    = "-" or <= 10 entries joined by "~": <mode>-<w|l|d>-<my36>-<their36>-<at36>,
               mode [a-z0-9]{1,12}
  ach = "-" or <unlocked36>-<total36>; cos = "-" or <owned36>-<equippedHex|->
  sig = "-" for now (reserved for a later signature, e.g. Ed25519; the addon doesn't check it yet)
  Max length 4096.
The addon: newest "issued" wins, older or duplicate snapshots are refused (no rollback), and it
shows NOT SYNCED after 7 days or past "expires". Build "Export snapshot" on the account page for
linked characters. No Shards or currencies in SRP1.

=== 4. Result import: SR1 (AGREED and vector-checked against the web's real verifyLog) ===
Rulesets (id + engine version = the rules):
  b120     timeCapMs 120000, capTicks 7200,  countdown 3000, startLevel 1, seed [a-z0-9-]{1,64}
  r180     timeCapMs 180000, capTicks 10800, countdown 4000, startLevel 1 (= web 1v1)
  daily120 timeCapMs 120000, capTicks 7200, seed exactly srwow-daily-YYYY-MM-DD (UTC date)
Challenge code (website -> WoW):  SR1C.<ruleset>.e<engine>.<seed>.<check>
  Web challenge seeds: "srchal-" + 10 random [a-z0-9] from server randomness (never from the date).
Result code (WoW -> website):
  SR1R.<platform>.<ruleset>.e<engine>.<seed>.<ticks36>.<score36>.<lines36>.<level36>.<hash>
      .<playerHex>.<link>.<log>.<check>
  hash = 8 hex, claimed hashState of the final state; log = compact input log (sr1.ts unpackInputs
  turns it into the web's SerializedInputLog losslessly); link = "-" or the character's linkId
  UPPERCASED (12 [A-Z0-9]). Max 32768 characters; a 2:00 result is ~1.5-2.5 KB.
Import algorithm (= importResult in tools/sr1/sr1.ts; the vectors pin the output and reason order):
  Inputs: the code, YOUR OWN record of the challenge (ruleset, seed, createdAtMs, closesAtMs; never
  taken from the code; a Daily runs 00:00 UTC to +24 h), and the server clock nowMs.
  1. Decode; on error reject with the decode error.
  2. ruleset differs -> ruleset_mismatch.   3. nowMs > closesAtMs -> expired.
  4. log = { v: engine, seed: codeSeed, startLevel: 1, ticks, inputs }.
  5. verifyLog({ log, seed: challenge.seed, timeCapMs, elapsedMs: nowMs - createdAtMs }) ->
     engine_mismatch, seed_mismatch, malformed_log, over_time_cap, faster_than_clock,
     inhuman_input_rate, inputs_after_topout.
  6. Append claim_mismatch (score/lines/level differ), then hash_mismatch.
  7. No reasons -> server_verified, else store as rejected with reasons (audit, never ranked).
Duplicates: runKey = <seed>.<ticks36>.<log>; store SHA-256(runKey) UNIQUE -> duplicate_run.
Boards: best server_verified score per player per challenge (players may retry offline).
Attribution: file a result under an account ONLY if link matches a binding with the same
character AND platform. Otherwise show "WoW: Name-Realm (unlinked)" and give no account anything.
Daily boards are fun boards, not ranked rewards (Daily seeds are public and can be prepared).
Not exported by WoW: Time Trial/Classic (private seeds), WoW duels (peer-checked), Spell Battle
(waits for SR2).

=== 5. Quickplay and multiplayer contracts (agree on names; no live connection) ===
- Trust vocabulary for every result: local | peer_checked | server_verified | rejected.
  Labels: "Verified by StackRivals" / "Checked by your opponent's addon" / "Not verified".
  Only server_verified may rank or reward. Never call a WoW duel "verified".
- Shared match record "stackrivals.match.v1" (schema, matchId, platform, mode, ruleset,
  engineVersion, seed, startedAt, endedAt, players[{playerRef, account, accountLink, score, lines,
  level, ticks, hash, log, forfeited}], outcome, verification, reasons, source). log is exactly
  the web's SerializedInputLog. Use it (or map to it) for stored results.
- Types to align with (tools/contract/types.ts): PlayerRef, AccountRef, Platform, MatchId,
  Ruleset, GameMode, EngineVersion, Seed, InputLog, SpellEvents, MatchResult, MatchVerification,
  ProfileSnapshot, CharacterProfile, MatchmakingStatus, MatchInvitation, MatchChatMessage.
- WoW Quickplay (Quick Duel) is WoW-only: it finds players through guild, group and friends
  inside WoW. The addon has a web adapter that honestly says "not connected". Do NOT build a web
  side for it. If you have ideas for a future allowed transport, describe them in your report only.
- WoW character cards (faction, race, class, level, duel record) are self-reported. Show them as
  unverified if they ever reach the website.
- SR2 (Spell Battle vs Bot results) is a DRAFT: review docs/SR2_DRAFT.md and answer its open
  questions; don't build it yet.

=== 6. What to build, in order ===
1. createLinkCode, submitLinkRequest(SRL1) -> binding, exportProfileSnapshot -> SRP1, unlink.
2. createChallenge -> SR1C (with createdAt/closesAt); a Daily board for daily120.
3. importResult(SR1R) page, exactly as section 4.
4. Rate limits (codes, imports per account and IP) and an audit log.
5. Unit tests that reproduce docs/vectors/account_v1.json and docs/vectors/sr1.json exactly.
Accepted when: every vector passes; a valid SR1R is server_verified; a forged one is rejected with
the importResult reasons; a WoW character links (SRL1 -> SRP1) and unlinks; no secret ever
appears in a code.

=== 7. Report back ===
What you built, the vector results (x/y passed), anything in SRL1 / SRP1 / SR2 that doesn't fit
(before building around it), and whether you want a snapshot signature scheme (and which).
````
