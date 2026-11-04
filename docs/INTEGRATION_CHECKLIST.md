# stackrivals.io ↔ WoW addon: integration checklist (before the CurseForge launch)

Use this when web Claude's integration report arrives. It works together with `docs/WEB_HANDOFF.md`
(formats, flows, trust). Every row says: what the addon already does, what the website must
deliver, which format must be agreed, which tests must pass, what's missing, and what needs a real
WoW test.

## Fixed principles (both projects)

* **The website is the authority** for accounts, XP, level, Shards, rank and season, achievements,
  cosmetic ownership and approved match results. The addon **displays** and **carries**; it never
  computes or grants any of them.
* **The addon builds no economy.** It has no Shards logic, no reward rates and no XP database.
* **No valuable reward from unverified WoW data.** Only results the website itself replays and
  approves (`server_verified`, e.g. an `SR1R` imported with `importResult`) may earn anything.
  * Replay proves the game events are legal. It does **not** prove a human played: a bot can produce
    a valid log. So the website decides which verified results may earn what, with its own limits.
  * WoW duels and Loot Duels are `peer_checked` and never reward.
* **No passwords, e-mails, session tokens or other secrets** in the addon or in any code.
  * Linking goes through the website, with one-time codes.
  * Nothing in a code is secret.
* **No connection exists** between a WoW addon and the internet. Every exchange is a code the player
  copies and pastes ("manual sync"). Automatic or real-time sync, and live Quickplay against web
  players, are **not possible** today and are never marketed as working.
* **No paid web subscription or purchase** is ever needed to use the addon.
* **Versioned contracts.** Every code starts with its format and version (`SRL1`, `SRP1`, `SR1C`,
  `SR1R`, …).
  * A newer version is refused with "update StackRivals", never guessed. The addon already does
    this for an `SRP2` it doesn't know yet.
  * An existing version never gets new fields: new data means a new version.
  * Older versions stay readable where that is safe.

## The checklist

| # | Integration point | Addon today (0.8.1) | Website must deliver | Format to agree | Tests that must pass | Missing | Real WoW test |
|---|---|---|---|---|---|---|---|
| 1 | **Account ID and linking** | Built: web code → `SRL1` link request → `SRP1` confirmation; PENDING / LINKED / NOT SYNCED; Unlink | Link page with one-time code (Crockford + check symbol, ~10 min, single use); checks `SRL1`; binding `{accountId, player, platform, linkId}`; unlink | `SRL1` + web code (draft v1; 84 Lua = TypeScript vectors) | `docs/vectors/account_v1.json` byte for byte on the web; addon `test_account.lua` | Web side; agreement of draft v1 | Typing / pasting codes in each client's edit boxes |
| 2 | **Player profile** (name, record, history) | Built: `SRP1` snapshot shown in the Profile tab (display only, expires 7 days) | "Export snapshot" producing `SRP1` | `SRP1` (draft v1) | vectors; addon profile tests | Web export | Paste a real `SRP1` |
| 3 | **XP and level** | Shown from `SRP1` (`level`, `xp`, `xpNext`) | The values, computed by the website | in `SRP1` | as #2 | The web's XP rules (theirs alone) | – |
| 4 | **Shards balance** | **Not shown yet** (`SRP1` has no field) | The balance in a profile snapshot, display only | **`SRP2` proposal** (below): `shards36` + `asOf` | new vectors for `SRP2`; the addon keeps reading `SRP1` | Web decision; then the addon parser + Profile row | Paste `SRP2` |
| 5 | **Rank and season** | Shown from `SRP1` (`rankHex`, `seasonHex`, `seasonPct`) | The values | in `SRP1` | as #2 | – | – |
| 6 | **Cosmetics and inventory** | Shown as a count + "wearing X" from `SRP1` (`cos`). Nothing is **applied** in WoW | List of owned / equipped cosmetic ids that WoW can render | `SRP2`: `equipped` ids per slot (board skin, piece set). Applying needs a **signed** snapshot | `SRP2` vectors; signature test vectors | WoW-side skins (art, ids), signature scheme, then "apply" | Look of each skin in each client |
| 7 | **Achievements** | Count from `SRP1` (`ach` = unlocked-total) | Unlocked list or count | `SRP1` count; a list would be `SRP2` | as #2 | List display (optional) | – |
| 8 | **Daily Challenges** | Built: daily seed `srwow-daily-YYYY-MM-DD`, today's best exported as `SR1R` (`daily120`); `SR1C` challenge codes played exactly | Daily board; `createChallenge` → `SR1C`; `importResult(SR1R)` | `SR1C` / `SR1R` (**agreed**, 77/77 vectors with the web's real `verifyLog`) | `docs/vectors/sr1.json`; a real WoW `SR1R` imports as `server_verified` | Web board and import page | Copy a 2–3 KB code out of WoW |
| 9 | **Match results / history** | Built: `SR1R` export (solo modes and challenges); history shown from `SRP1` | `importResult` + history in the next snapshot | `SR1R` (agreed); Spell Battle results: `SR2` (**draft**, `docs/SR2_DRAFT.md`) | as #8; `SR2` vectors once agreed | `SR2` agreement and both sides | as #8 |
| 10 | **Reward eligibility** | Nothing in the addon (by design) | Rules on the website: only `server_verified`, with its own anti-bot limits | none in WoW | web tests | Web only | – |
| 11 | **Signed snapshots** | `sig` field reserved, not checked | A signing scheme (e.g. Ed25519 public key in the addon) | `SRP1`/`SRP2` `sig` | sign/verify vectors | Web proposal, then an addon verifier in pure Lua | – |
| 12 | **Quickplay / shared matchmaking** | WoW Quickplay works between WoW players; the web adapter honestly shows "not connected" | Nothing possible without a transport | – | – | A verified transport (none exists) | – |

## Proposal for the website: `SRP2` (profile snapshot v2, DRAFT for web Claude to accept or change)

`SRP2` would be `SRP1`'s fields in the same order, plus:

```
.<shards36>.<asOf36>.<equipped>.<achList>
  shards36   Shards balance, base 36 (display only; "-" = not shown)
  asOf36     unix seconds the balance and rank were read on the website
  equipped   "-" or slot:id pairs joined by "~", e.g. board:neon~pieces:classic  (ids [a-z0-9_]{1,24})
  achList    "-" or up to 10 recent achievement ids joined by "~"
```

* `sig` stays reserved until a scheme is agreed.
* **Without a valid `sig`, the addon never applies a cosmetic. It only names it.**
* The addon reads `SRP1` and `SRP2`. An unknown `SRP3` is refused with "update".
* **Nothing is built until web Claude agrees.** The fields, their order and the limits come from
  the website. This is only a proposal, so we don't each invent our own.

## When web Claude's report arrives

1. Compare each changed contract with the table: format, version, field order, limits, vectors.
2. Agree or push back **before** building. Never adapt silently to a format that breaks the
   principles above (rewards from unverified data, secrets in codes, a paid requirement).
3. Build the addon side on the existing code (`Net/AccountCodes.lua`, `Core/Account.lua`,
   `UI/AccountUI.lua`, `Net/Codes.lua`). Start from the existing code, not from scratch.
4. Tests:
   * the web's vectors must reproduce byte for byte in Lua (CI);
   * old versions must still read;
   * a newer version must be refused with "update";
   * the client-profile tests must still pass.
5. Joint QA (phase 3): link a real WoW character, play, export, import on the website, then check
   the profile back in WoW. Do this on Forever and Classic Era.

## Tasks waiting for the website

1. Agree on, or change, draft v1: the web link code, `SRL1` and `SRP1`.
2. Build the Link page, the `SRL1` check, the binding, the `SRP1` export and unlink.
3. Decide on `SRP2`: the Shards display, equipped cosmetics, achievements and `asOf`.
4. Propose a snapshot signature scheme, so cosmetics can be applied in WoW.
5. Build the Daily board, `createChallenge` (`SR1C`) and `importResult` (`SR1R`).
6. Agree on `SR2` (Spell Battle results), or decide to postpone it.
7. Set reward and XP rules for WoW-originated, `server_verified` results, including the website's
   anti-bot limits.
8. Provide cosmetic ids and art references, if WoW should show skins.
9. Fix the web live-loop items in `docs/WEB_SPELL_REPORT.md`.
