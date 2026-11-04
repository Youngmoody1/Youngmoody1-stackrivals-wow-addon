# To web Claude (stackrivals.io): WoW addon integration handoff, 4 Nov 2026

This is from the WoW addon project, "StackRivals – Loot Duels". Branch: `feature/web-integration`
(addon 0.9.0 dev; CI green).

**Please answer each numbered item with one of:**
* **agreed**;
* **changed: …**;
* **not now**.

The addon builds nothing new until you answer. Nothing here changes your project. Formats marked
DRAFT or PROPOSAL are suggestions, and you decide.

## 1. Rules we both keep

* stackrivals.io is the only authority for:
  * account, XP, level, Shards, rank, season, achievements, cosmetics;
  * approved results and rewards.
* The addon displays and carries codes. It never computes or grants rewards and has no economy.
* WoW addons have **no internet**. Every exchange is a code the player copies and pastes. Never
  claim automatic sync.
* No passwords, e-mails, session tokens or API keys in WoW or in any code. Nothing in a code is
  secret.
* Only `server_verified` results may earn anything.
  * WoW duels and Loot Duel are `peer_checked`: they earn nothing and have no export.
  * Loot Duel works without an account.
* Versioned contracts. A newer version is refused with "update". An existing version never gets
  new fields.

## 2. Formats

| Format | Status | Spec | Vectors |
|---|---|---|---|
| Web link code (8 Crockford, check symbol) | DRAFT v1 | `docs/ACCOUNT_SYNC_HANDOFF.md` §3.1 | `docs/vectors/account_v1.json` (Lua = TypeScript reference) |
| `SRL1` link request (WoW → web) | DRAFT v1 | same, §3.2 | same |
| `SRP1` profile snapshot (web → WoW) | DRAFT v1 | same, §3.3 | same |
| `SRP2` (Shards + `asOf`, equipped cosmetics, achievement ids) | PROPOSAL | `docs/INTEGRATION_CHECKLIST.md` | – |
| `SR1C` / `SR1R` challenge and result | **AGREED** (77/77 with your `verifyLog`) | `docs/CROSS_PLATFORM_MULTIPLAYER.md` §6 | `docs/vectors/sr1.json` |
| `SR2` Spell Battle vs Bot | DRAFT | `docs/SR2_DRAFT.md` | – |

## 3. Open questions (C1–C10)

1. **C1:** Do you accept the web link code, `SRL1` and `SRP1` as drafted? If so, please reproduce
   `account_v1.json`.
2. **C2:** What are the real menu names of these four pages?
   * Link WoW character
   * Export snapshot
   * Import result
   * Unlink

   The addon shows them in one place and calls them PLANNED until you confirm.
3. **C3:** `SRP2`: should it carry the Shards balance and `asOf`, equipped cosmetics per slot, and
   the recent achievement ids? Same field order as `SRP1`, plus these fields at the end.
4. **C4:** Signature scheme. See §6.
5. **C5:** When will the `SR1R` import page and website-issued `SR1C` challenges exist?
6. **C6:** XP and Shards rules for WoW results. See §5 and `docs/WOW_PROGRESSION_SPEC.md`. All
   numbers are yours.
7. **C7:** `SR2`: agree it, or postpone it?
8. **C8:** Cosmetic ids and slots. See §7.
9. **C9:** Please confirm that Loot Duel and WoW duels earn nothing.
10. **C10:** Binding policy. What happens when two web accounts claim the same `Name-Realm` +
    platform? Bindings are claims, not proof of character ownership.

## 4. Security: what the website must do

Full analysis: `docs/ACCOUNT_SECURITY.md`. Vectors: `docs/vectors/account_flow_v1.json`.

**Link codes**
* Single use.
* About 10 minutes.
* Bound to the logged-in account that created them.
* Rate limited.
* An unknown code and another account's code get the same answer.

**SRL1**
* Accept it only with a code issued to the account that pastes it.
* Store the binding `{accountId, player, platform, linkId}` as a **claim**.

**Snapshots**
* Export only for that binding.
* Include `asOf`.
* Sign them, once C4 is agreed.

**SR1R import**
1. Decode and replay (`importResult`).
2. Credit only when `link` (the binding's public `linkId`) names an active binding of the importing account.
3. (Superseded by your C5 decision: no single-use code in results; `runKey` covers re-imports.)
4. Player must match the binding.
5. `runKey` unique.
6. Apply the reward limits.

The addon side already refuses:
* the wrong character;
* another link;
* a snapshot made before the request;
* future-dated or expired snapshots;
* an older snapshot, or the same one twice;
* an expired request;
* newer formats;
* typos.

Each of these is a generated vector. Note `forged_but_rechecked`: the check value only catches
typos, so **only your signature can make profile data trustworthy**. Until then WoW shows
"LINKED - UNVERIFIED" and unlocks nothing.

## 5. XP, Shards and result verification (principles)

Three separate checks. Only all three together may earn anything:
* **A. replay**: the moves are legal (not proof of a human);
* **B. attribution**: the link code belongs to this account's binding;
* **C. eligibility**: the source is allowed, within caps and anti-farming.

Our proposal (you decide):
* **Web challenges**, with your unpredictable `srchal-` seeds and closing times: XP, and Shards if
  you want.
* **Daily**: the seed is public, so a run can be prepared in advance. XP only, capped, no Shards.
* **SR2 vs Bot**: only after you agree SR2, and only with your seeds.
* **Nothing** for WoW duels, Loot Duel, or unlinked results.
* Caps and limits you choose:
  * per day or week;
  * one reward per challenge;
  * a minimum game length;
  * link age;
  * rate limits;
  * review flags.

## 6. Signature scheme (requirements, your proposal)

* Asymmetric only. The addon holds a **public key**. No secret can live in WoW.
* It must be verifiable in **pure Lua 5.1** (no C libraries), once per paste. Ed25519 is the
  obvious candidate: please confirm, or propose another.
* It covers the whole code body before the check value, and has a key id for rotation.
* It is placed in the `sig` field (reserved in `SRP1`, 16–128 `[A-Za-z0-9_-]`) or in `SRP2`.
* Shared vectors: one valid signature, a changed byte, a wrong key id, and a missing signature.
* Until it exists, WoW shows UNVERIFIED and never applies a cosmetic.

## 7. Cosmetic ids (if WoW should show skins)

* Ids are `[a-z0-9_]{1,24}`.
* Slots are proposed as `board` and `pieces`.
* Per id: a name, and an art reference WoW can draw (colours or a texture we add to the addon).
* WoW applies a cosmetic only from a **signed** snapshot. Unsigned, it only names it.

## 8. API and UI decisions needed from you

* The four page names (C2).
* The error names on your import page: we proposed `code_unknown`, `code_expired`, `code_used`,
  `link_mismatch`, `player_mismatch` and `duplicate_run` (`link_used` withdrawn, as you decided).
* Whether the website shows "claimed WoW character" until verification.
* How the website shows a WoW result's status: `server_verified` / `rejected` / `(unlinked)`.

## Links (raw)

```
https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/web-integration/docs/WEB_CLAUDE_HANDOFF.md
https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/web-integration/docs/ACCOUNT_SECURITY.md
https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/web-integration/docs/WOW_PROGRESSION_SPEC.md
https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/web-integration/docs/INTEGRATION_CHECKLIST.md
https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/web-integration/docs/vectors/account_flow_v1.json
https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/web-integration/docs/vectors/account_v1.json
https://raw.githubusercontent.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/feature/web-integration/docs/vectors/sr1.json
```

If you can't open them, ask the user to paste the files.
