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
| 2 | **Player profile** (name, record, history) | Built: `SRP1` snapshot shown in the Profile tab (display only, expires 7 days). Since 0.9.0-dev the tab reads a format-independent view (`Account.profileView()`). A strip at the bottom says "Last update 26 Oct 2026, 08:36 - 12 days ago" (calendar days), "Pasted by hand, so it may be out of date. Nothing unlocks in WoW.", and shows an UNVERIFIED tag. After 7 days it says OUT OF DATE in gold. Long names, ranks and cosmetics are cut with "..." | "Export snapshot" producing `SRP1` | `SRP1` (draft v1) | vectors; addon profile tests | Web export | Paste a real `SRP1` |
| 3 | **XP and level** | Shown from `SRP1` (`level`, `xp`, `xpNext`) | The values, computed by the website | in `SRP1` | as #2 | The web's XP rules (theirs alone) | – |
| 4 | **Shards balance** | **Not shown yet** (`SRP1` has no field). Prepared in 0.9.0-dev: the view has a `shards` field (always empty for `SRP1`). The Profile tab shows "12,480 SHARDS" next to the record only when an approved format fills it (preview `23c3`, simulated). No parser, no arithmetic | The balance in a profile snapshot, display only | **`SRP2` proposal** (below): `shards36` + `asOf` | new vectors for `SRP2`; the addon keeps reading `SRP1` | Web decision; then the addon parser + Profile row | Paste `SRP2` |
| 5 | **Rank and season** | Shown from `SRP1` (`rankHex`, `seasonHex`, `seasonPct`) | The values | in `SRP1` | as #2 | – | – |
| 6 | **Cosmetics and inventory** | Shown as a count + "wearing X" from `SRP1` (`cos`). Nothing is **applied** in WoW | List of owned / equipped cosmetic ids that WoW can render | `SRP2`: `equipped` ids per slot (board skin, piece set). Applying needs a **signed** snapshot | `SRP2` vectors; signature test vectors | WoW-side skins (art, ids), signature scheme, then "apply" | Look of each skin in each client |
| 7 | **Achievements** | Count from `SRP1` (`ach` = unlocked-total) | Unlocked list or count | `SRP1` count; a list would be `SRP2` | as #2 | List display (optional) | – |
| 8 | **Daily Challenges** | Built: daily seed `srwow-daily-YYYY-MM-DD`, today's best exported as `SR1R` (`daily120`); `SR1C` challenge codes played exactly | Daily board; `createChallenge` → `SR1C`; `importResult(SR1R)` | `SR1C` / `SR1R` (**agreed**, 77/77 vectors with the web's real `verifyLog`) | `docs/vectors/sr1.json`; a real WoW `SR1R` imports as `server_verified` | Web board and import page | Copy a 2–3 KB code out of WoW |
| 9 | **Match results / history** | Built: `SR1R` export (solo modes and challenges); history shown from `SRP1` | `importResult` + history in the next snapshot | `SR1R` (agreed); Spell Battle results: `SR2` (**draft**, `docs/SR2_DRAFT.md`) | as #8; `SR2` vectors once agreed | `SR2` agreement and both sides | as #8 |
| 10 | **Reward eligibility** (XP / Shards from WoW play) | Nothing in the addon (by design). Proposal for the website: `docs/WOW_PROGRESSION_SPEC.md` (sources, eligibility, anti-farming, caps, import flow) | Rules on the website: only `server_verified`, with its own anti-bot limits and caps | none in WoW | web tests | Web decisions (spec §6) | – |
| 11 | **Signed snapshots** | `sig` field reserved, not checked. The Profile tab says UNVERIFIED (VERIFIED in green once a scheme exists). Nothing is unlocked from an unsigned snapshot | A signing scheme (e.g. Ed25519 public key in the addon) | `SRP1`/`SRP2` `sig` | sign/verify vectors | Web proposal, then an addon verifier in pure Lua | – |
| 12 | **Quickplay / shared matchmaking** | WoW Quickplay works between WoW players; the web adapter honestly shows "not connected" | Nothing possible without a transport | – | – | A verified transport (none exists) | – |

## `SRP2` v1: defined by the website (replaces this project's proposal)

The website answered the proposal with its own **SRP2 v1**:
* the spec is `docs/WOW_SRP2.md` and the TypeScript reference is `src/lib/wow/srp2.ts`, both in the web repo;
* the vectors are `docs/vectors/srp2_v1.json` (16 parse + 9 signature cases) and the catalog is
  `docs/vectors/cosmetics_catalog_v1.json`, both copied here unchanged.

What it contains:
* Shards and `asOf`;
* `equipped`, per slot `skin`, `frame` and `victory`;
* `owned`;
* `events` (Overdrive value = multiplier × 100);
* the SRP2-SIG v1 signature.

`achList` was dropped. **`SRP1` is unchanged.** The addon reads both, and refuses `SRP3` with "update".

## When web Claude's report arrives (reception process)

The report goes through these steps **in order**. Nothing is built in step 1–3; nothing in the
website project is changed from the addon chat.

**1. Receive and file (same day)**
* Save the report as `docs/web-reports/YYYY-MM-DD.md`, exactly as received.
* List every contract it touches (`SRL1`, `SRP1`, `SRP2`, `SR1C`, `SR1R`, `SR2`, signatures, reward
  rules) and every vector file it ships.

**2. Compare the contracts (table per format)**

| Check | How |
|---|---|
| Format name and version | Same prefix and number as the table above; a changed meaning = a new version |
| Field order, types, limits | Field by field against `Net/AccountCodes.lua` / `Net/Codes.lua` and `WEB_HANDOFF.md` §2 |
| Vectors | The web's vector files reproduce byte for byte in Lua (added to CI before any code) |
| Principles | No reward from `peer_checked` data (WoW duels, Loot Duels); no secret in any code; no paid requirement; the website stays the authority |
| Old formats | `SRP1` and existing `SR1R` codes stay readable; existing SavedVariables stay valid |
| Overlap | Does the report add something the addon already has (codes, daily seed, history)? Then reuse, never a second copy |

Result of step 2: a short reply to web Claude, per format: **agreed** / **changes needed (why)** /
**not now**. The user approves the reply before it is sent.

**3. Plan (after agreement)**
* Map each new field into the existing view (`Account.profileView()`), never directly into the UI.
* List the files to change; new modules only when no existing one fits.
* Note which real WoW tests the change needs (Forever and Classic Era at least).

**4. Build (on `feature/web-integration`, never on `alpha/0.8.1`)**
* Parser in `Net/AccountCodes.lua` next to the existing one; `Acc.import` keeps one code path.
* UI only through the view (Shards row, cosmetics names, "Last updated").
* A cosmetic is **named** only; it is applied only with a verified signature (row 11).

**5. Tests that must pass before anything is called ready**
* the web's vectors (byte for byte), in CI on Lua 5.1;
* old formats: an `SRP1` snapshot and a 0.7.0 SavedVariables fixture still load and show;
* the next unknown version (e.g. `SRP3`) is refused with "update", and the current profile is kept;
* signatures: a good one passes, a changed byte fails, a missing one shows "not checked";
* XP / Shards / results flow: export `SR1R` → (website replays) → next snapshot shows the
  website's XP, level and Shards; the addon never computes or changes them;
* Loot Duel still runs with no account and never calls Account / Sync
  (`test_lootduel.lua`, "works without any stackrivals.io account");
* every client profile in `test_clients.lua`.

**6. Joint QA (RELEASE_PLAN phase 3)**: link a real character, play, export, import on the
website, paste the new snapshot back, check the Profile tab. Forever and Classic Era. Results go in
the test logs, never from simulations.

## Web contracts C1–C10 (status after the website's answers, 4 Nov 2026)

| # | Contract | Status | Blocks |
|---|---|---|---|
| C1 | Web link code + `SRL1` + `SRP1` (draft v1) | **AGREED** by the website (all vectors reproduced) | – |
| C2 | Menu names | **AGREED**: stackrivals.io/wow > Link WoW character, Sync status > Export snapshot / Unlink; Import result planned. In `Account.WEB` | – |
| C3 | Shards, cosmetics, events | **DEFINED by the website: `SRP2` v1**. Parser + import (web-Claude, `4e08d86`), **Collection tab** (0.9.0) | the website's SRP2 export on /wow (built, waits for publishing) |
| C4 | Signatures | **SRP1-SIG v1 / SRP2-SIG v1** (Ed25519). **Verifier built in pure Lua 5.1**, all web vectors pass | the **production public key** from the owner |
| C5 | `SR1R` import, `SR1C` challenges | **NOT NOW** (web branch only). Attribution rule changed: `link` = public `linkId`, not single-use | – |
| C6 | XP / Shards from WoW results | **NOT NOW** (no rewards from manual sync) | – |
| C7 | `SR2` | **NOT NOW** | – |
| C8 | Cosmetic art in WoW | **NOT NOW**: names from the catalog; nothing drawn; any future drawing only via `Account.canApplyCosmetic` (VERIFIED) | – |
| C9 | Loot Duel / WoW duels earn nothing | **AGREED**; enforced by a test | – |
| C10 | One character, two accounts | **CHANGED**: one ACTIVE binding per platform + Name-Realm; a new link moves it | – |

Website pages the addon names (all **PLANNED**, none exists yet; names in `Account.WEB`, to be
replaced with the real ones): Link WoW character, Export snapshot, Import result, Unlink.

Negative test vectors for both sides: `docs/vectors/account_flow_v1.json` (16 addon import cases
generated by running the addon, 17 website checks).

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
