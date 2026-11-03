# StackRivals web ↔ WoW integration contract (v1, DRAFT)

Addon 0.6.1, branch `feature/connected`. This is the master contract both projects build against.
**Nothing here is final until stackrivals.io agrees.** SR1 is the exception: it is built and
vector-checked against the web. Status words: **BUILT** (in the addon, tested between simulated
clients), **SIMULATED** (no real WoW client yet), **PROPOSED** (needs the web), **BLOCKED**
(impossible or not allowed today).

Machine-readable sources:

* types: `tools/contract/types.ts` (TypeScript, type-checked);
* account codes: `tools/contract/account.ts` (TypeScript reference) and `StackRivals/Net/AccountCodes.lua`;
* SR1: `tools/sr1/sr1.ts` and `StackRivals/Net/Codes.lua`;
* vectors: `docs/vectors/sr1.json`, `docs/vectors/account_v1.json`.

Each vector file is made by the Lua addon and passes the TypeScript reference:

* SR1: 77/77 at web `29afe52`;
* account: 84/84 with `bun tools/contract/check_account_vectors.ts`.

## 1. Account linking (BUILT addon side, PROPOSED web side)

One account, owned by the website. A WoW character links to it with a one-time code and two
copy and paste codes. The steps:

1. The web code `A7K9-P2XJ`.
2. The addon makes an `SRL1` request.
3. The website returns an `SRP1` confirmation.

The addon shows **Linked** only after that confirmation for its own `linkId` and character. A typed
code alone is **Pending**. There are no passwords, e-mails or tokens in WoW.

Full flow, formats, errors, conflicts and the website's to-do list are in
`docs/ACCOUNT_SYNC_HANDOFF.md`. Types: `AccountRef`, `AccountLink`, `PlayerRef` in `types.ts`.

| Lua (addon) | TypeScript | Notes |
|---|---|---|
| `db.accounts["Name-Realm"].link = {linkId, accountId, at}` | `AccountLink` | per character |
| `Account.state()` → `not_linked\|pending\|linked\|not_synced` | (UI only) | Linked needs the website's SRP1 |

## 2. PlayerProfile and CharacterProfile (BUILT, display only)

* **PlayerProfile / ProfileSnapshot.** The website's profile: name, rank, level, XP, season,
  W/L/D, history, achievements and cosmetics. In WoW it is shown from the last imported SRP1
  snapshot, marked with its date, and never authoritative. There are no Shards or currencies.
* **CharacterProfile.** One WoW character as its own addon reports it to a rival (`PRF`):
  * from the WoW API on its own PC: faction, race, class, level;
  * from local SavedVariables: duel W/L;
  * the chat on/off setting;
  * **self-reported** apart from the name and realm, which WoW checks;
  * "Share my card" off → all Unknown.

Details: `docs/WOW_QUICKPLAY_HANDOFF.md` section 3. Types: `ProfileSnapshot`, `PlayerProfile`,
`CharacterProfile`.

## 3. Quickplay matchmaking events (BUILT native, BLOCKED web)

* **Native (WoW ↔ WoW).** The pool is players who are searching and that this client can reach:
  guild, party / raid, friends and Battle.net friends whose StackRivals answered, and recent
  rivals.
  * `QS` advertises a search.
  * The lower name invites with `INV …:q`.
  * The other side accepts automatically only while it is searching for the same mode.
* **Web adapter.** `Quickplay.adapters.web` has the interface `status()/search()/cancel()` and
  always reports `not_connected`. There is no fake queue.
* **Events** (`MatchmakingEvent`), in order: `search_started` → `matched` → `ready` (both) →
  `countdown` → `started` → `result` → optional `rematch_requested`.
  * Plus `search_cancelled`, `no_opponent` (after 5 min) and `fell_through` (the rival didn't get
    ready: they are skipped for 2 min and the search goes on).
* **Status** (`MatchmakingStatus`): `idle | searching | matched | none`, the mode, the reach, the
  adapter states and a note.

## 4. Match invitations and ready states (BUILT, protocol v1 unchanged)

* **Invitation.** `MatchInvitation`, carried by `1:INV:<mid>:<ruleset>:<engine>:<commitA>[:q]`.
  * The seed is commit-reveal: `srduel-<mid>-<nonceA><nonceB>`.
  * Rematch is a new invite with `rematch: true`, and the rival must accept it.
* **States** (`ReadyState`): `invited → lobby → (ready ×2) → playing → waiting → done`, or
  `cancelled` with a reason (declined, busy, combat, version, timeout, lobby timeout, offline).
* **Lobby.** Both press Ready within 60 s, the countdown starts, and every fairness rule applies:
  * shared pauses, 60 s budget each;
  * combat pause;
  * clock check;
  * peer replay;
  * verdict exchange.

Protocol reference: `docs/CROSS_PLATFORM_MULTIPLAYER.md` §3.

## 5. Match chat (BUILT, SIMULATED)

`MatchChatMessage`, carried by `CH` (text, hex UTF-8, ≤ 80 bytes) and `QM` (quick message 1–4).

* It goes by addon whisper to the rival only. It is never posted to a WoW channel and never
  stored.
* Both players must have chat on.
* Free text works within one faction only. Across factions, quick messages only.
* Rate limits: sending 1 per 1.5 s and 8 per 30 s; receiving at most 10 per 30 s.
* `|` is escaped.
* Mute is remembered, and the muted player is not told.

The website has no part in WoW match chat. It could reuse the same message shape for web matches
if it wants to.

## 6. Multiplayer protocol (BUILT, prefix `StackRivals`, protocol 1)

| Messages | Since | Purpose |
|---|---|---|
| HEL, HI | 0.4 | presence |
| INV, ACC, DEC, RDY, GO, PNG, SC, END, LOG, RQ, FIN, BYE | 0.4 | duel |
| SP, PSE, RSM, VER | 0.5 | spells, shared pauses, verdicts |
| QS, PRF, CH, QM, INV flag `q` | 0.6.1 | Quickplay, cards, chat |

* Unknown kinds are ignored, so older clients never break.
* Every message is ≤ 255 bytes, `[A-Za-z0-9.:,-]` only, with strict field counts and ranges.
* The web never sees these messages. They are WoW ↔ WoW only.

## 7. SR1 / SR2 data formats

* **SR1 (BUILT, vector-checked with the web):**
  * challenge `SR1C.<ruleset>.e<engine>.<seed>.<check>`;
  * result `SR1R.<platform>.<ruleset>.e<engine>.<seed>.<ticks>.<score>.<lines>.<level>.<hash>.<playerHex>.<link>.<log>.<check>`;
  * rulesets `b120`, `r180`, `daily120`.

  Spec: `docs/CROSS_PLATFORM_MULTIPLAYER.md` §6.
* **SR2 (DRAFT, not built):** Spell Battle vs Bot results, with cast letters in the log.
  `docs/SR2_DRAFT.md`.
* **SRL1 / SRP1 (DRAFT v1, BUILT addon side):** account link request and profile snapshot.
  `docs/ACCOUNT_SYNC_HANDOFF.md`.
* **Shared record** `stackrivals.match.v1` = `MatchResult` in `types.ts`, the record the website
  stores.
* **Compatibility rules:**
  * Every code starts with its format and version (`SR1R`, `SRP1`, …). A newer version is refused
    with "update" (`version`), never guessed.
  * Fields are never added to an existing version. A change means a new version, and the old one
    keeps working until both sides drop it together.
  * The engine version is part of every result. Records compare only within one engine version.
    Old ones are archived, never deleted.
  * Unknown values, wrong field counts and non-canonical numbers are refused, never
    "best effort".

## 8. Profile import (BUILT addon side)

Account → paste `SRP1` → checks:

* format and check;
* this character;
* the same `linkId`;
* not expired or in the future (±10 min);
* newer than the last snapshot (no rollback, no duplicate).

The result is display only. It can't change records, duel results, Quickplay cards or anything on
the website (tested).

## 9. Result export (BUILT addon side, PROPOSED web import)

Account → Sync:

* **Paste an `SR1C` challenge.** The addon plays exactly that challenge (ruleset and seed), not as
  a local record. "Play again" repeats it.
* **Exportable results:**
  * the last 10 finished challenges;
  * today's best Daily Challenge run (`daily120`, seed `srwow-daily-<UTC date>`).

  Each becomes an `SR1R` code to copy (1.5–3.5 KB).
* **The link field** = this character's `linkId`, uppercased (12 `[A-Z0-9]`, fits SR1's
  `[A-Z0-9]{6,12}`), when linked; otherwise `-`. The website may file the result under the linked
  account **only if** the binding for that `linkId` has the same character and platform.
* **Not exportable:**
  * Time Trial and Classic (private seeds the website never issued);
  * WoW duels (peer-checked only);
  * Spell Battle (waits for SR2).

## 10. Server verification and trust boundaries

| Data | Trusted by | Why |
|---|---|---|
| SR1 result | the website, **after its own `verifyLog` replay** | the log is the proof; the check digits only catch typos |
| WoW duel result | the two PCs (peer replay) | never server-verified; never ranked on the web |
| Character name / realm | WoW (real sender) | can't be faked inside WoW; outside WoW (a pasted code) it is a claim |
| Faction / race / class / level / duel W-L | nobody (self-reported) | shown as "unverified" |
| Profile snapshot in WoW | nobody in WoW (display only) | anyone can type a code; `sig` reserved for a later web signature |
| Link (`linkId`) | the website's stored binding | a `linkId` in a code is a claim until it matches a binding |
| SavedVariables | nothing | the player can edit them; cleaned on load, never authoritative |

Rewards, ranking, XP and progression are decided **only** by the website from server-verified data.

## 11. What web Claude must implement

1. Link WoW character: the one-time code, SRL1 check, the binding, and SRP1 export (confirm and
   later), unlink, rate limits and audit (`ACCOUNT_SYNC_HANDOFF.md` §8).
2. SR1 import page: paste an `SR1R` code, decode, check against the website's own challenge
   record, `verifyLog`, unique run key, then store `server_verified` or `rejected`. If the `link`
   field matches a binding with the same character, file it under that account. `importResult` in
   `tools/sr1/sr1.ts` is the algorithm.
3. SR1 challenge creation: `srchal-` seeds and an `SR1C` code to copy, with `createdAt` and
   `closesAt`. A Daily board uses `daily120` with the shared date seed.
4. Reproduce `docs/vectors/sr1.json` and `docs/vectors/account_v1.json` in unit tests.
5. Optional: agree or adjust SR2 (`docs/SR2_DRAFT.md`) and fix the two live-loop bugs noted in
   `docs/WEB_SPELL_REPORT.md`.
6. Nothing for WoW Quickplay or chat: those stay inside WoW.

## 12. What the WoW addon can't do alone

* Reach the internet: no HTTP, no WebSocket. All sync is copy and paste, or a future companion
  (`ACCOUNT_SYNC_HANDOFF.md` §7, research only).
* Live WoW ↔ web matches or a shared Quickplay queue: no allowed transport exists (BLOCKED).
* Find strangers: no global addon channel in Classic. It finds only players it can reach.
* Verify anything about another player except their character name, or verify a profile's origin
  (no signature check yet).
* Rank, reward or grant progression.
* Talk across factions with free text (WoW's rule). Whether cross-faction addon whispers arrive at
  all **needs a real client test**.
* Reach non-friends on other realms. Battle.net friends on any realm are reached over Battle.net
  game data (0.6.1, simulated; `docs/CHALLENGE_FRIENDS.md`). Anyone else needs a connected realm.

## Prompt for web Claude

See `docs/WEB_ADDON_INTEGRATION_HANDOFF.md` §12. It is the same prompt, ready to paste.
