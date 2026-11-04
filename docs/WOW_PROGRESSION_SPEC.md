# XP and Shards from WoW play: integration specification (PROPOSAL for stackrivals.io)

Status: **proposal from the addon project, 4 Nov 2026. Nothing here is built, and no rate is set.**
stackrivals.io decides every rule, number and cap. The addon only carries codes and shows what the
website sends back.

Goal: players can earn progression by playing in WoW, so they come back to both the addon and the
website. This must not allow endless farming and must not reward manipulated results. There is
**one progression system, on the website**. The addon has no XP database, no Shards logic and no
reward rates.

## 1. Fixed principles

1. **The website is the only authority.** It decides XP, level, Shards, rank, season, achievements
   and cosmetics. The addon never computes, grants, predicts or spends any of them.
2. **Only `server_verified` results can earn anything.** The website must have replayed the result
   itself (`importResult` for SR1, `verifySpellMatch` for SR2 once agreed).
   * `peer_checked` results never earn: WoW duels, Quick Duel, Guild Duels and Loot Duel.
   * `local` results never earn.
3. **A linked account is required to earn.** An unlinked result can appear on a board as
   "WoW: Name-Realm (unlinked)" but earns nothing for anyone (CROSS_PLATFORM_MULTIPLAYER.md §6.5).
4. **Replay proves the moves were legal, not that a human made them.** A bot playing in real time
   produces a valid log on every platform. So rewards also need limits (§4), not only replay.
5. **No new reward without a new contract.** The addon shows a number (XP, Shards) only when an
   approved, versioned snapshot format carries it (`SRP2` or later).
6. **Loot Duel stays without economic rewards.** That holds until the website proposes a separate,
   secure and approved scheme. The addon proves this in a test: Loot Duel never calls Account or
   Sync (`test_lootduel.lua`).

## 1b. Three different questions (never merge them)

| Level | Question | Who answers it | What it proves |
|---|---|---|---|
| **A. Legal replay** | Do the game events in this log produce this score? | Website: `importResult` / `verifySpellMatch` | The moves are legal and match the claim. **Not** that a human played: a real-time bot passes |
| **B. Account attribution** | Whose result is it? | Website: the result's `link` (the public `linkId`) must name an active binding of the importing account; player + platform match it; `runKey` unique globally | The result belongs to that account's **claimed** WoW character. Not proof of character ownership (only Battle.net OAuth would be) |
| **C. Reward eligibility** | Does it earn XP / Shards now? | Website: source allowed (§3), within caps and limits (§4), account rules (age, flags) | Only A + B + C together may earn anything |

A result can pass A and fail B (someone else's run), or pass A and B and fail C (over the cap, or
Daily Shards). The addon answers none of these: it only carries the code.

## 2. What WoW can send, and what the website can verify

| Source in WoW | Code | Seed chosen by | Server can replay? | Can be prepared in advance? | Proposal |
|---|---|---|---|---|---|
| **Web challenge** played in WoW (2:00 / 3:00) | `SR1C` in → `SR1R` out (`b120`, `r180`) | the **website** (`srchal-` + server randomness), with a closing time | **Yes**: `importResult`, agreed with 77/77 vectors | **No**: the seed is unknown before the challenge exists; `faster_than_clock` | **Best candidate** for XP and, if the website wants, Shards |
| **Shared Daily** | `SR1R` (`daily120`, seed `srwow-daily-<UTC date>`) | **public** (the date) | **Yes** | **Yes**: the seed is predictable, so a tool-assisted run can be prepared | XP with a small daily cap at most. **No Shards** (fun board) |
| **Spell Battle vs Bot** | `SR2R` (**draft**, SR2_DRAFT.md) | the website (`SR2C`) or the addon | Yes, once SR2 is agreed (`verifySpellMatch`) | Only if the addon picks the seed | After SR2 is agreed: XP for website-issued `SR2C` seeds only |
| Solo Classic / Time Trial | not exported | the addon | — | yes | Nothing (not exported today) |
| WoW duels, Quick Duel, Guild Duels | not exported | the two players' addons | No (peer-checked; two players can collude) | yes | **Nothing** |
| **Loot Duel** (2–40) | not exported | the group (commit–reveal) | No (peer-checked) | — | **Nothing** until a separate approved scheme exists |

## 3. Suggested eligibility (the website decides; names only, no numbers)

| Result | XP | Shards | Board |
|---|---|---|---|
| `server_verified` web challenge, linked account, first valid import for that challenge | yes: `xpPerChallenge` (website) | optional: `shardsPerChallenge` (website) | ranked |
| Better attempt at the same challenge | none, or only the difference | none | best attempt shown |
| `server_verified` Daily, linked | yes, capped: `xpPerDaily`, at most once per date | **no** | fun board |
| SR2 vs Bot (after agreement), website seed | yes: `xpPerBotMatch` by difficulty | no (proposal) | — |
| `rejected`, `local`, `peer_checked`, unlinked | no | no | not ranked |

## 4. Anti-bot and anti-farming (website side)

**What replay already gives** (agreed SR1 algorithm, §6.4–6.5):
* `claim_mismatch` and `hash_mismatch`;
* `over_time_cap` and `faster_than_clock`;
* `inhuman_input_rate` and `inputs_after_topout`;
* `expired` once a board has closed;
* `duplicate_run`: one run, one owner, via `SHA-256(runKey)` UNIQUE.

**Extra limits we propose** (the website picks which, and every number):
* **Caps per account:** `dailyXpCap`, `weeklyShardsCap`, and a maximum number of rewarded imports
  per day.
* **One reward per challenge:** the first valid import earns; better attempts at the same challenge
  update only the board.
* **Unpredictable seeds for anything valuable:** only website-issued `srchal-` seeds earn Shards.
  Never Daily or addon-chosen seeds.
* **Closing windows:** a challenge closes after `CHALLENGE_TTL_MS`. Old seeds can't be farmed.
* **Diminishing returns:** later rewarded runs on the same day earn less.
* **Minimum effort:** a reward needs a minimum game length or score, so instant top-outs earn
  nothing.
* **Link required, and link age:** a newly linked character can't earn Shards for the first N days.
* **Rate limits** per account and per IP on the import page.
* **Review flags:** collect, don't auto-ban.
  * Duplicate runs under other names.
  * Unusual input timing.
  * Many accounts on one IP.
  * Sudden score jumps.
* **Bots playing in real time can't be fully detected by replay.** Keep values modest and use the
  caps.

## 5. Safe import flow (manual copy and paste, no connection)

1. In WoW the player plays a web challenge, pasted on the Sync tab as `SR1C…`, or the Daily.
2. The Sync tab shows the result code (`SR1R…`). The player copies it with Ctrl+C.
3. On stackrivals.io the player logs in and opens **Account > WoW > Import result** (provisional
   name). They paste the code.
4. The website runs the following, all on the server:
   1. decode;
   2. look up its own challenge record — `ruleset`, `seed` and `closesAtMs` come from the website,
      never from the code;
   3. replay;
   4. check the run key and the binding: the same character and platform as the link;
   5. apply the limits from §4;
   6. compute the reward with its own rules, store it and show it.
5. The website's next profile snapshot carries the new XP, level and Shards. The player exports it
   (**Account > WoW > Export snapshot**) and pastes it on the WoW Account tab.
6. WoW shows the new values with "Last update …" and its UNVERIFIED / VERIFIED tag. Until signatures
   exist, the values are shown only and unlock nothing in WoW.

No passwords, tokens or secrets are ever in a code or in WoW. A result's `link` is the binding's public
`linkId`: a selector, not a secret and not single-use. Only the signed-in owner of that binding can import
against it, and `runKey` stops re-imports (the website's decision, C5).

## 6. Decisions needed from stackrivals.io

1. Which sources earn XP and which earn Shards (§3). Is Daily XP-only?
2. The numbers and caps: `xpPerChallenge`, `shardsPerChallenge`, `xpPerDaily`, `dailyXpCap`,
   `weeklyShardsCap`, and the minimum game length.
3. The real menu names for Link, Export snapshot, Import result and Unlink. The addon has them in
   one table, `Account.WEB`.
4. `SRP2`: the field for the Shards balance and an `asOf` time (INTEGRATION_CHECKLIST.md).
5. A signature scheme for snapshots, so the addon can tell VERIFIED from UNVERIFIED and apply
   cosmetics safely.
6. Whether SR2 (Spell Battle vs Bot) is agreed now or postponed.
7. Confirmation that Loot Duel and WoW duels earn nothing.

When these are answered, the addon side is:
* a parser for the agreed snapshot format;
* the existing Profile view, which already has the Shards slot and the "Last update" strip;
* the Sync tab, which already exports `SR1R`.

There is no reward logic on the addon side.
